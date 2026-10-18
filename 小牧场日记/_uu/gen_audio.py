#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""《小牧场日记》程序化音频生成器（8/16-bit chiptune 风格）。

为什么用 Python 现算而不是找素材：
  项目里 27 个 SFX、1 条雨声环境音、7 首 BGM 的**文件名 / 时长 / 循环方式**都被
  AudioManager 和音频数据表当成硬契约（见 data/audio.csv）。素材网上下载的 wav
  时长不可控、授权也不干净；程序化合成则能精确到样本点地满足「0.12s 就是 5292
  个样本」「BGM 首尾必须无缝」这类要求，而且改一个参数就能重生成，方便以后调音。
  脚本不依赖任何外部素材、不联网、不调用 ffmpeg，只用标准库 wave + numpy。

用法：
    python _uu/gen_audio.py
  每次运行都会**覆盖**重写全部输出；随机数全部用固定种子，重复运行字节完全一致。

输出：
    audio/sfx/<id>.wav     单声道 44100Hz 16-bit，峰值 -6 dBFS
    audio/sfx/rain_loop.wav 4.0s 无缝循环环境音
    audio/bgm/<id>.wav     立体声 44100Hz 16-bit，峰值 -12 dBFS，无缝循环

关键实现思路（为什么这样写）：
  * 相位累加：所有振荡器只吃「相位（单位：圈）」而不是时间/频率，这样滑音、
    颤音只是把频率数组先算成相位再喂进去，同一套 square/triangle 不用改。
  * 可复用 ADSR / 指数衰减包络：打击乐用 exp_env（衰减时间常数 tau 好调），
    持续音用 adsr（起音/衰减/保持/释放四段，听感更像真实乐器包络）。
  * 一阶 IIR 低通：chiptune 的方波/噪声高频太扎，必须靠低通做出「闷」「沙」
    的质感；这里用 y[n]=y[n-1]+a*(x[n]-y[n-1])，a 由截止频率推出。
  * BGM 用「环形缓冲」合成：把所有音符（包括尾巴）按样本位置取模叠加到长度恰为
    整小节的缓冲里，超出的尾音自然绕回开头，所以循环点没有静音/爆音，不需要
    再叠 crossfade（crossfade 会改变响度、反而听得出接缝）。
  * 环形噪声：环境音/雨层用「随机相位 + 频谱整形 + irfft」，得到的波形周期严格
    等于整段长度，天然无缝，比「白噪声截断」干净得多。
"""

import math
import os
import sys
import wave

import numpy as np

# ---------------------------------------------------------------- 基础常量 ----

SR = 44100                              # 全项目统一采样率，Godot 导入不需要重采样
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))  # 项目根（_uu 的上一层）
SFX_DIR = os.path.join(ROOT, "audio", "sfx")
BGM_DIR = os.path.join(ROOT, "audio", "bgm")

# 脚本里的 id 就是文件名，改这里等于改契约，必须和 data/audio.csv 对齐
SFX_SPEC = (
    # (id, 时长秒, 构建函数, 随机种子, 一句说明)
    ("step_grass",      0.12, None, 1101),
    ("step_dirt",       0.12, None, 1102),
    ("step_wood",       0.12, None, 1103),
    ("hoe",             0.28, None, 1104),
    ("water",           0.70, None, 1105),
    ("plant",           0.30, None, 1106),
    ("milk",            0.55, None, 1107),
    ("egg",             0.40, None, 1108),
    ("shears",          0.30, None, 1109),
    ("coin",            0.35, None, 1110),
    ("ui_open",         0.18, None, 1111),
    ("ui_close",        0.18, None, 1112),
    ("ui_click",        0.07, None, 1113),
    ("animal_cow",      0.90, None, 1114),
    ("animal_goat",     0.70, None, 1115),
    ("animal_sheep",    0.70, None, 1116),
    ("animal_alpaca",   0.60, None, 1117),
    ("animal_pig",      0.50, None, 1118),
    ("animal_chicken",  0.45, None, 1119),
    ("animal_duck",     0.45, None, 1120),
    ("animal_turkey",   0.60, None, 1121),
    ("animal_bee",      0.40, None, 1122),
    ("build_place",     0.35, None, 1123),
    ("build_done",      0.80, None, 1124),
    ("save",            0.45, None, 1125),
    ("eat",             0.35, None, 1126),
    ("craft",           0.45, None, 1127),
)


# ------------------------------------------------------------ 基础 DSP 工具 ----

def n_of(dur):
    """秒 -> 样本数（四舍五入）。契约里的时长必须是「整样本」，否则 WAV 头写的
    nframes 会和设计值差 1，测试里按秒比会飘。"""
    return max(1, int(round(dur * SR)))


def db_to_amp(db):
    """分贝 -> 线性幅度。峰值 -6dBFS 约等于 0.501，-12dBFS 约等于 0.251。"""
    return 10.0 ** (db / 20.0)


def midi_hz(midi):
    """MIDI 音高 -> 频率（A4=69=440Hz）。全项目统一用 MIDI 号写旋律，避免写频率表。"""
    return 440.0 * 2.0 ** ((float(midi) - 69.0) / 12.0)


def phase_of(freq, n):
    """频率曲线 -> 相位（圈）。用累加而不是 freq*t，是因为滑音/颤音时频率逐样本变，
    瞬时相位必须积分出来，否则会有相位跳变造成「咔哒」声。"""
    f = np.asarray(freq, dtype=np.float64)
    if f.ndim == 0:
        f = np.full(n, float(f))
    elif len(f) != n:
        raise ValueError("freq 曲线长度 %d 与样本数 %d 不一致" % (len(f), n))
    return np.cumsum(f) / SR


def square(ph, duty=0.5):
    """方波：占空比决定音色。0.5 最饱满；0.25/0.125 更「细」、更像 FC 时代的伴奏。"""
    return np.where((ph % 1.0) < duty, 1.0, -1.0)


def triangle(ph):
    """三角波：谐波比方波少，用来做低音和柔和长音，叠在方波旋律下不会打架。"""
    return 4.0 * np.abs((ph % 1.0) - 0.5) - 1.0


def sine(ph):
    return np.sin(2.0 * np.pi * ph)


def osc(kind, ph, duty=0.5):
    """按名字取波形，方便同一段音序器代码给不同曲目换音色。"""
    if kind == "square":
        return square(ph, duty)
    if kind == "triangle":
        return triangle(ph)
    if kind == "sine":
        return sine(ph)
    raise ValueError("未知波形: %r" % (kind,))


def noise(n, rng):
    """白噪声。注意用传入的 rng，而不是全局 np.random，保证每个文件/每首曲子
    的随机序列只由自己的固定种子决定（换生成顺序也不会改变已生成文件的字节）。"""
    return rng.standard_normal(n)


def lowpass(x, cutoff):
    """一阶 IIR 低通（单极点）。用途：把噪声压成「闷响」、把方波磨圆。

    为什么手写循环而不是 scipy：
      运行时只有 numpy，一阶 IIR 递推 y[n]=y[n-1]+a*(x[n]-y[n-1]) 在 Python 里
      对 SFX/鼓点这种几千样本的短缓冲足够快，也不引入新依赖。
    """
    a = 1.0 - math.exp(-2.0 * math.pi * float(cutoff) / SR)
    x = np.asarray(x, dtype=np.float64)
    y = np.empty_like(x)
    acc = 0.0
    for i in range(len(x)):
        acc += a * (x[i] - acc)
        y[i] = acc
    return y


def highpass(x, cutoff):
    """一阶高通 = 原信号减低通。用来做「咔哒」「沙粒」「金属擦」这类高频瞬态。"""
    return np.asarray(x, dtype=np.float64) - lowpass(x, cutoff)


def dc_block(x, cutoff=22.0):
    """去直流（约 22Hz 的一阶高通）。

    为什么必须做：方波占空比不等于 50% 时本身就有直流分量（0.25 占空比 = -0.5），
    整段只有一声长音时整个文件会带上明显 DC 偏置。DC 偏置不发声，但会：
      ① 吃掉峰值余量（归一化后有效响度变小）；
      ② 播放器开始/结束时因为 0 与非 0 的跳变产生「噗」声。
    22Hz 低于人耳/游戏 BGM 的低音范围，去掉它听不出区别。
    """
    return np.asarray(x, dtype=np.float64) - lowpass(x, cutoff)


def exp_env(n, tau, attack=0.001):
    """指数衰减包络。tau 是「衰减到 1/e 的时间常数」，tau 越小越干脆。

    attack 段用几毫秒线性淡入而不是理想的 0 起音：数字合成里瞬起会产生宽带咔哒，
    实际听感「干脆」的来源是衰减快，而不是真的 0 秒起音。
    """
    tt = np.arange(n, dtype=np.float64) / SR
    env = np.exp(-tt / max(float(tau), 1e-6))
    a = int(max(1, min(n, round(float(attack) * SR))))
    env[:a] *= np.linspace(0.0, 1.0, a)
    return env


def adsr(n, a=0.005, d=0.05, s=0.65, r=0.08, curve=1.5):
    """四段包络（attack/decay/sustain/release），段长按 n 自动裁剪。

    「为什么曲线用 curve 次方」：线性衰减听起来像机械拉杆，指数感衰减更像乐器/
    人声的自然衰减；release 端用 (1-k)^curve 保证最后一个样本精确为 0。
    """
    a_n = int(min(n, round(max(0.0, a) * SR)))
    d_n = int(min(n - a_n, round(max(0.0, d) * SR)))
    r_n = int(min(n - a_n - d_n, round(max(0.0, r) * SR)))
    s_n = n - a_n - d_n - r_n
    env = np.empty(n, dtype=np.float64)

    if a_n:
        env[:a_n] = np.linspace(0.0, 1.0, a_n, endpoint=False)
    if d_n:
        k = np.linspace(0.0, 1.0, d_n)
        env[a_n:a_n + d_n] = s + (1.0 - s) * (1.0 - k) ** curve
    if s_n:
        env[a_n + d_n:a_n + d_n + s_n] = s
    if r_n:
        k = np.linspace(0.0, 1.0, r_n)
        env[n - r_n:] = s * (1.0 - k) ** curve
    if not a_n and not d_n and not r_n:
        env[:] = s
    return env


def fade_out(x, dur=0.010):
    """尾部淡出。契约要求 SFX 最后 10ms 内归零：不做的话播放结束时的瞬时截断
    会有「噗」的一声，尤其在噪声类音效上特别明显。"""
    x = np.asarray(x, dtype=np.float64)
    k = min(len(x), int(round(dur * SR)))
    if k > 0:
        x[-k:] *= np.linspace(1.0, 0.0, k)
    return x


def normalize_peak(x, peak_db):
    """按峰值归一化到指定 dBFS。用峰值而不是 RMS：SFX 要求「峰值 −6 dBFS 左右」，
    统一峰值能让 27 个音效在游戏里音量一致；RMS 归一会让长音比短音听上去闷。"""
    x = np.asarray(x, dtype=np.float64)
    peak = float(np.max(np.abs(x)))
    if peak <= 1e-12:
        raise ValueError("空信号无法归一化")
    return x * (db_to_amp(peak_db) / peak)


def mix_into(buf, sig, pos_sec=0.0, gain=1.0):
    """把一段短信号叠加进整段缓冲（非循环用，超出末尾的部分直接截断）。"""
    start = int(round(pos_sec * SR))
    if start >= len(buf) or start < 0:
        return
    sig = np.asarray(sig, dtype=np.float64)
    m = min(len(sig), len(buf) - start)
    if m > 0:
        buf[start:start + m] += gain * sig[:m]


def add_circular(buf, sig, start_sample):
    """环形叠加：BGM/环境音无缝循环的核心。

    缓冲长度 = 一个循环周期。把音符放到 start，超过结尾的样本写回开头——等价于
    在无限周期信号上叠加，因此 x[N-1] 与 x[0] 在原始波形里本来就是相邻样本，
    循环接缝不存在。注意这里**不能**把尾巴截掉再淡出，那样就变成一次性音效了。
    """
    n = len(buf)
    if n == 0:
        return
    sig = np.asarray(sig, dtype=np.float64)
    if len(sig) == 0:
        return
    if len(sig) > n:                     # 防御：单音不应长于整段循环
        sig = sig[:n]
    pos = int(round(start_sample)) % n
    end = pos + len(sig)
    if end <= n:
        buf[pos:end] += sig
    else:
        k = n - pos
        buf[pos:] += sig[:k]
        rest = sig[k:]
        buf[:len(rest)] += rest


def tone(midi, dur, kind="square", duty=0.25, tau=0.08, attack=0.002, second=0.0):
    """一个短音符（用于 SFX 里的叮、拨弦、琶音）。second 是叠加八度泛音的比例。"""
    n = n_of(dur)
    f = midi_hz(midi)
    ph = phase_of(f, n)
    sig = osc(kind, ph, duty)
    if second:
        sig = sig + second * osc("sine", ph * 2.0)
    return sig * exp_env(n, tau, attack)


def bubble(f0, dur=0.06, up=0.9, gain=1.0, attack=0.0015):
    """气泡音：频率从 f0 向上滑、指数衰减。浇水/挤奶的「咕嘟」都靠它。"""
    n = n_of(dur)
    f = f0 * (1.0 + up * np.linspace(0.0, 1.0, n))
    sig = sine(phase_of(f, n)) * exp_env(n, dur * 0.35, attack)
    return sig * gain


# ---------------------------------------------------------------- SFX 构建 ----

# 每个函数都返回「长度正好 n」的单声道浮点缓冲；输出前的淡出/归一化在 make_sfx 里统一做，
# 这样每个音效只需要关心自己的音色，不会各写一套收尾逻辑。

def s_step_grass(n, rng):
    """踩草：低通噪声的软闷响 + 一点低频落地感。草是「吸音」的，所以高频要压掉。"""
    buf = np.zeros(n)
    soft = lowpass(noise(n, rng), 800.0) * exp_env(n, 0.028, 0.0015)
    mix_into(buf, soft, 0.002, 1.0)
    thud = sine(phase_of(95.0, n)) * exp_env(n, 0.025, 0.001)
    mix_into(buf, thud, 0.0, 0.35)
    return buf


def s_step_dirt(n, rng):
    """踩泥土：比草地更「沙」，用更高的低通 + 少量未滤高频颗粒，再加更低的闷响。"""
    buf = np.zeros(n)
    body = lowpass(noise(n, rng), 1400.0) * exp_env(n, 0.030, 0.0015)
    mix_into(buf, body, 0.0, 1.0)
    grit = highpass(noise(n, rng), 3000.0) * exp_env(n, 0.018, 0.001)
    mix_into(buf, grit, 0.001, 0.30)
    thud = sine(phase_of(72.0, n)) * exp_env(n, 0.030, 0.001)
    mix_into(buf, thud, 0.0, 0.40)
    return buf


def s_step_wood(n, rng):
    """木地板：木鱼感的短促共鸣。两个不成整数比的衰减正弦叠出「木头」而非「鼓」。"""
    buf = np.zeros(n)
    body = (sine(phase_of(392.0, n)) * exp_env(n, 0.022, 0.0008)
            + 0.5 * sine(phase_of(884.0, n)) * exp_env(n, 0.012, 0.0005))
    mix_into(buf, body, 0.0, 1.0)
    click = highpass(noise(n, rng), 4500.0) * exp_env(n, 0.004, 0.0003)
    mix_into(buf, click, 0.0, 0.55)
    return buf


def s_hoe(n, rng):
    """锄地：噪声爆发（翻土）+ 低频方波闷响（锄头砸地），再加第二下碎土。"""
    buf = np.zeros(n)
    burst = lowpass(noise(n, rng), 2200.0) * exp_env(n, 0.055, 0.0015)
    mix_into(buf, burst, 0.0, 1.0)
    crack = highpass(noise(n, rng), 3500.0) * exp_env(n, 0.020, 0.0008)
    mix_into(buf, crack, 0.0, 0.45)
    tt = np.arange(n) / SR
    f = 48.0 + 85.0 * np.exp(-tt * 6.0)        # 85Hz 往 48Hz 掉，才有「砸下去」的重量
    thud = lowpass(square(phase_of(f, n), 0.5), 320.0) * exp_env(n, 0.090, 0.002)
    mix_into(buf, thud, 0.0, 0.85)
    crumb = lowpass(noise(n, rng), 1200.0) * exp_env(n, 0.035, 0.001)
    mix_into(buf, crumb, 0.11, 0.35)
    return buf


def s_water(n, rng):
    """浇水：噪声先渐强（水柱形成）再收，气泡在中间随机冒出。"""
    buf = np.zeros(n)
    tt = np.arange(n) / SR
    # 渐强 0.22s，随后缓慢收尾；保留一点底噪让「水」是连续的而不是断开的
    swell = np.clip(tt / 0.22, 0.0, 1.0) ** 1.5
    swell *= 1.0 - np.clip((tt - 0.48) / 0.22, 0.0, 1.0)
    stream = (lowpass(noise(n, rng), 1800.0) + 0.30 * highpass(noise(n, rng), 4200.0))
    mix_into(buf, stream * swell, 0.0, 1.0)
    for pos, f0 in ((0.10, 520.0), (0.21, 760.0), (0.32, 610.0), (0.43, 880.0), (0.53, 700.0)):
        mix_into(buf, bubble(f0, up=0.8, gain=0.55), pos, 0.55)
    return buf


def s_plant(n, rng):
    """播种：pop（土被按开的短促下坠）+ 轻拨弦（种子落定），拨弦用三角波更「木」。"""
    buf = np.zeros(n)
    m = n_of(0.10)
    f = 70.0 + 150.0 * np.exp(-np.arange(m) / SR * 22.0)
    mix_into(buf, sine(phase_of(f, m)) * exp_env(m, 0.030, 0.001), 0.0, 0.9)
    pluck = tone(76, 0.22, kind="triangle", tau=0.10, attack=0.002, second=0.25)
    mix_into(buf, pluck, 0.045, 0.55)
    return buf


def s_milk(n, rng):
    """挤奶「滋滋」：上升方波短音（奶柱一下一下）+ 细碎气泡噪声底。"""
    buf = np.zeros(n)
    for pos in (0.02, 0.15, 0.28):
        m = n_of(0.11)
        f = 300.0 + 260.0 * (np.arange(m) / m) ** 0.6
        blip = square(phase_of(f, m), 0.25) * adsr(m, 0.004, 0.03, 0.5, 0.05)
        mix_into(buf, blip, pos, 0.55)
    sizzle = lowpass(noise(n, rng), 3500.0) * np.clip(np.arange(n) / SR / 0.18, 0.0, 1.0)
    sizzle *= np.exp(-np.arange(n) / SR / 0.55)
    mix_into(buf, sizzle, 0.0, 0.75)
    for pos, f0 in ((0.19, 600.0), (0.34, 900.0), (0.46, 720.0)):
        mix_into(buf, bubble(f0, up=0.9, gain=0.45), pos, 0.5)
    return buf


def s_egg(n, rng):
    """捡蛋：三声「咯咯」的短方波（带 38Hz 幅度调制做颗粒感）+ 最后 pop。"""
    buf = np.zeros(n)
    for pos, f0 in ((0.02, 950.0), (0.10, 820.0), (0.18, 1000.0)):
        m = n_of(0.055)
        tt = np.arange(m) / SR
        f = f0 - 120.0 * (tt / 0.055)
        cluck = square(phase_of(f, m), 0.35) * adsr(m, 0.002, 0.02, 0.4, 0.02)
        cluck *= 0.7 + 0.3 * np.sin(2.0 * np.pi * 38.0 * tt)
        mix_into(buf, cluck, pos, 0.60)
    m = n_of(0.12)
    pop = sine(phase_of(np.linspace(300.0, 90.0, m), m)) * exp_env(m, 0.035, 0.001)
    mix_into(buf, pop, 0.285, 0.8)
    return buf


def s_shears(n, rng):
    """剪刀：两下高频金属「咔」。用高次泛音 + 高通噪声，短到 20ms 内衰减完才像金属。
    两下间隔 0.17s，让 0.30s 的文件末尾只留一点点余响，而不是拖半段静音。"""
    buf = np.zeros(n)
    for pos, base in ((0.020, 2800.0), (0.190, 3400.0)):
        m = n_of(0.075)
        tt = np.arange(m) / SR
        f = base * (1.0 - 0.12 * tt / 0.075)
        ring = (sine(phase_of(f, m)) + 0.6 * sine(phase_of(f * 1.5, m))
                + 0.25 * sine(phase_of(f * 2.4, m))) * exp_env(m, 0.014, 0.0005)
        click = highpass(noise(m, rng), 5000.0) * exp_env(m, 0.004, 0.0003)
        mix_into(buf, ring * 0.7 + click * 0.5, pos, 0.8)
    return buf


def s_coin(n, rng):
    """金币：B5→E6 两音，方波 0.25 占空比 + 快速衰减，经典 8-bit 收钱声。"""
    buf = np.zeros(n)
    for midi, dur, pos, gain in ((83, 0.14, 0.0, 0.60), (88, 0.20, 0.10, 0.65)):
        sig = tone(midi, dur, kind="square", duty=0.25, tau=0.07, attack=0.0015)
        mix_into(buf, sig, pos, gain)
    sparkle = tone(100, 0.05, kind="sine", tau=0.02, attack=0.001)  # E7 一点点闪光
    mix_into(buf, sparkle, 0.10, 0.18)
    return buf


def s_ui_open(n, rng):
    """界面打开：上行 blip。指数扫频比线性更像「嗖」地弹出来。"""
    tt = np.arange(n) / SR
    f = 520.0 * np.exp(np.log(1350.0 / 520.0) * np.clip(tt / 0.10, 0.0, 1.0))
    sig = square(phase_of(f, n), 0.25) * adsr(n, 0.004, 0.03, 0.55, 0.05)
    return sig


def s_ui_close(n, rng):
    """界面关闭：下行 blip，和 ui_open 互为镜像。"""
    tt = np.arange(n) / SR
    f = 1350.0 * np.exp(np.log(520.0 / 1350.0) * np.clip(tt / 0.10, 0.0, 1.0))
    sig = square(phase_of(f, n), 0.25) * adsr(n, 0.004, 0.03, 0.55, 0.05)
    return sig


def s_ui_click(n, rng):
    """按钮点击：短 tick。高频「嗒」+ 一点木鱼低音，让 70ms 的文件听起来是一声
    完整的点击而不是「响一下就挂在那儿」——UI 音效拖静音尾巴会显得掉帧。"""
    buf = np.zeros(n)
    tick = highpass(noise(n, rng), 3000.0) * exp_env(n, 0.010, 0.0003)
    mix_into(buf, tick, 0.0, 0.8)
    blip = square(phase_of(1800.0, n), 0.5) * exp_env(n, 0.008, 0.0005)
    mix_into(buf, blip, 0.0, 0.35)
    wood = sine(phase_of(760.0, n)) * exp_env(n, 0.020, 0.0008)
    mix_into(buf, wood, 0.0, 0.45)
    return buf


def s_animal_cow(n, rng):
    """牛叫：低方波 + 下滑音 + 慢颤音。低通 700Hz 去掉方波的高频边角，
    留下「哞」的圆润；7Hz 幅度调制模拟喉咙的颤动。"""
    tt = np.arange(n) / SR
    dur = n / SR
    f = 118.0 - 26.0 * (tt / dur) + 4.0 * np.sin(2.0 * np.pi * 4.5 * tt)
    ph = phase_of(f, n)
    sig = lowpass(0.65 * square(ph, 0.5) + 0.35 * triangle(ph), 700.0)
    env = adsr(n, 0.09, 0.15, 0.75, 0.30, 1.5)
    sig *= env * (0.8 + 0.2 * np.sin(2.0 * np.pi * 7.0 * tt))
    return sig


def s_animal_goat(n, rng):
    """山羊叫：比绵羊更亮、更快、更抖。基频 620→500Hz，11Hz 颤音 depth 22Hz。"""
    tt = np.arange(n) / SR
    dur = n / SR
    vib = 22.0 * np.sin(2.0 * np.pi * 11.0 * tt)
    f = 620.0 - 120.0 * (tt / dur) + vib
    ph = phase_of(f, n)
    sig = 0.6 * square(ph, 0.4) + 0.4 * triangle(ph)
    sig *= adsr(n, 0.03, 0.12, 0.7, 0.14, 1.3)
    sig *= 0.75 + 0.25 * np.sin(2.0 * np.pi * 6.0 * tt)
    return sig


def s_animal_sheep(n, rng):
    """绵羊叫：中频「咩」，颤音比山羊慢、浅，声音更钝（低通 1500Hz）。"""
    tt = np.arange(n) / SR
    dur = n / SR
    f = 385.0 + 9.0 * np.sin(2.0 * np.pi * 7.0 * tt) - 35.0 * (tt / dur)
    ph = phase_of(f, n)
    sig = lowpass(0.55 * square(ph, 0.45) + 0.45 * triangle(ph), 1500.0)
    sig *= adsr(n, 0.04, 0.12, 0.72, 0.16, 1.3)
    sig *= 0.72 + 0.28 * np.sin(2.0 * np.pi * 5.0 * tt)   # 羊的「抖」比山羊更明显
    return sig


def s_animal_alpaca(n, rng):
    """羊驼：鼻音哼哼，低中频短促两下。方波过 900Hz 低通保留鼻音，气声用低通噪声。"""
    buf = np.zeros(n)
    for pos, f0 in ((0.04, 250.0), (0.30, 225.0)):
        m = n_of(0.19)
        tt = np.arange(m) / SR
        f = f0 - 40.0 * (tt / 0.19) + 3.0 * np.sin(2.0 * np.pi * 6.0 * tt)
        sig = lowpass(square(phase_of(f, m), 0.42), 900.0)
        sig *= adsr(m, 0.03, 0.06, 0.65, 0.07, 1.4)
        mix_into(buf, sig, pos, 0.9)
    breath = lowpass(noise(n, rng), 700.0) * np.clip(np.arange(n) / SR / 0.08, 0.0, 1.0)
    breath *= np.exp(-np.arange(n) / SR / 0.30)
    mix_into(buf, breath, 0.02, 0.25)
    return buf


def s_animal_pig(n, rng):
    """猪叫：低中频「哼哧」。噪声（喷气）+ 下滑方波（喉咙），22Hz 幅度调制做鼻音颗粒。"""
    buf = np.zeros(n)
    for pos, f0, dur in ((0.0, 170.0, 0.16), (0.22, 150.0, 0.20)):
        m = n_of(dur)
        tt = np.arange(m) / SR
        f = f0 - 55.0 * (tt / dur)
        sig = 0.6 * square(phase_of(f, m), 0.5) + 0.4 * lowpass(noise(m, rng), 900.0)
        sig *= exp_env(m, dur * 0.5, 0.004) * (0.7 + 0.3 * np.sin(2.0 * np.pi * 22.0 * tt))
        mix_into(buf, sig, pos, 0.85)
    snort = lowpass(noise(n, rng), 1400.0) * exp_env(n, 0.05, 0.002)
    mix_into(buf, snort, 0.0, 0.30)
    return buf


def s_animal_chicken(n, rng):
    """鸡叫：四声短促「咯咯」，频率一高一低、末尾上挑，颗粒感靠 45Hz 幅度调制。
    0.45s 里从 0.01 铺到 0.385，结尾只留 60ms 呼吸，不会出现半段静音。"""
    buf = np.zeros(n)
    for pos, f0 in ((0.010, 900.0), (0.115, 1150.0), (0.220, 980.0), (0.325, 1280.0)):
        m = n_of(0.06)
        tt = np.arange(m) / SR
        f = f0 * (1.0 + 0.10 * np.sin(2.0 * np.pi * 18.0 * tt))
        sig = square(phase_of(f, m), 0.3) * adsr(m, 0.002, 0.02, 0.45, 0.025)
        sig *= 0.7 + 0.3 * np.sin(2.0 * np.pi * 45.0 * tt)
        mix_into(buf, sig, pos, 0.55)
    return buf


def s_animal_duck(n, rng):
    """鸭叫：噪声 + 方波一起下滑，「嘎」的沙哑感来自噪声占比高、且带 25Hz 颤。"""
    buf = np.zeros(n)
    tt = np.arange(n) / SR
    dur = n / SR
    f = 340.0 - 150.0 * (tt / dur) + 12.0 * np.sin(2.0 * np.pi * 25.0 * tt)
    ph = phase_of(f, n)
    sig = 0.45 * square(ph, 0.35) + 0.55 * lowpass(noise(n, rng), 2200.0)
    sig *= adsr(n, 0.015, 0.10, 0.7, 0.12, 1.3)
    sig *= 0.65 + 0.35 * np.sin(2.0 * np.pi * 25.0 * tt)
    return sig


def s_animal_turkey(n, rng):
    """火鸡：快速「咕咕咕」三连。每下 0.12s，方波 540→390Hz，32Hz 调制做明显的颗粒；
    三下铺满 0.02~0.48s，0.6s 的文件末尾留 0.12s 的余响，不是一整段空白。"""
    buf = np.zeros(n)
    for pos, f0 in ((0.020, 540.0), (0.190, 500.0), (0.360, 460.0)):
        m = n_of(0.12)
        tt = np.arange(m) / SR
        f = f0 - 150.0 * (tt / 0.12)
        sig = square(phase_of(f, m), 0.4) * adsr(m, 0.003, 0.03, 0.55, 0.05)
        sig *= 0.55 + 0.45 * np.sin(2.0 * np.pi * 32.0 * tt)
        mix_into(buf, sig, pos, 0.6)
    click = highpass(noise(n, rng), 1500.0) * exp_env(n, 0.03, 0.001)
    mix_into(buf, click, 0.0, 0.15)
    return buf


def s_animal_bee(n, rng):
    """蜜蜂：方波 + 快速颤音（28Hz）。颤音太慢会变成警报，28Hz 才像翅膀振动。"""
    tt = np.arange(n) / SR
    f = 225.0 + 18.0 * np.sin(2.0 * np.pi * 28.0 * tt)
    ph = phase_of(f, n)
    sig = 0.7 * square(ph, 0.5) + 0.3 * square(ph * 2.0, 0.5)
    sig *= adsr(n, 0.02, 0.08, 0.8, 0.10, 1.2)
    sig *= 0.75 + 0.25 * np.sin(2.0 * np.pi * 9.0 * tt)   # 9Hz 近远感
    return sig


def s_build_place(n, rng):
    """放置建筑：木敲 + 低频落地。两下敲击（第二下更轻）让「放下去」有重量。"""
    buf = np.zeros(n)
    for pos, gain in ((0.0, 1.0), (0.17, 0.55)):
        m = n_of(0.14)
        knock = (sine(phase_of(310.0, m)) * exp_env(m, 0.035, 0.001)
                 + 0.45 * sine(phase_of(760.0, m)) * exp_env(m, 0.018, 0.0006))
        click = highpass(noise(m, rng), 3800.0) * exp_env(m, 0.006, 0.0004)
        mix_into(buf, knock + 0.5 * click, pos, 0.8 * gain)
    tt = np.arange(n) / SR
    thud = sine(phase_of(48.0 + 45.0 * np.exp(-tt * 8.0), n)) * exp_env(n, 0.10, 0.002)
    mix_into(buf, thud, 0.0, 0.9)
    return buf


def s_build_done(n, rng):
    """竣工：短琶音小号角。C5-E5-G5-C6 依次点出，最后一个音拖长收尾，有「完成」感。"""
    buf = np.zeros(n)
    for midi, dur, pos, gain in ((72, 0.11, 0.00, 0.55), (76, 0.11, 0.10, 0.55),
                                 (79, 0.11, 0.20, 0.55), (84, 0.46, 0.31, 0.65)):
        sig = tone(midi, dur, kind="square", duty=0.25, tau=min(0.30, dur * 0.9),
                   attack=0.002, second=0.20)
        mix_into(buf, sig, pos, gain)
    # 最后一个和弦垫一下，小号角才有厚度
    for midi in (76, 79):
        mix_into(buf, tone(midi, 0.42, kind="triangle", tau=0.35, attack=0.01), 0.31, 0.18)
    return buf


def s_save(n, rng):
    """存档：两声确认音（E5→A5），第二声带一点上滑，听起来像「叮—咚」的确认。"""
    buf = np.zeros(n)
    mix_into(buf, tone(76, 0.16, kind="square", duty=0.25, tau=0.10, attack=0.002), 0.01, 0.55)
    m = n_of(0.24)
    f = 880.0 * (1.0 + 0.06 * np.linspace(0.0, 1.0, m))
    second = square(phase_of(f, m), 0.25) * exp_env(m, 0.13, 0.002)
    mix_into(buf, second, 0.15, 0.60)
    mix_into(buf, highpass(noise(n, rng), 5000.0) * exp_env(n, 0.004, 0.0003), 0.01, 0.10)
    return buf


def s_eat(n, rng):
    """吃东西：四口脆响噪声。每口用「低通 2600 + 高通 900」的带通噪声，短促衰减才有脆感。"""
    buf = np.zeros(n)
    for pos, gain in ((0.01, 1.0), (0.09, 0.8), (0.17, 0.9), (0.25, 0.7)):
        m = n_of(0.07)
        crunch = lowpass(noise(m, rng), 2600.0)
        crunch = highpass(crunch, 900.0) * exp_env(m, 0.022, 0.001)
        body = sine(phase_of(180.0, m)) * exp_env(m, 0.018, 0.001)
        mix_into(buf, crunch * 0.85 + body * 0.25, pos, gain)
    return buf


def s_craft(n, rng):
    """加工：金属叮 + 撞击。叮用不成整数比的三个泛音（像铁砧），撞击是短低频噪声。"""
    buf = np.zeros(n)
    m = n_of(0.40)
    tt = np.arange(m) / SR
    ding = np.zeros(m)
    for ratio, tau, gain in ((1.0, 0.16, 1.0), (1.47, 0.09, 0.55), (2.31, 0.05, 0.35)):
        ding += gain * sine(phase_of(1200.0 * ratio, m)) * exp_env(m, tau, 0.0008)
    mix_into(buf, ding, 0.02, 0.55)
    impact = lowpass(noise(n, rng), 900.0) * exp_env(n, 0.06, 0.001)
    mix_into(buf, impact, 0.19, 0.55)
    thud = sine(phase_of(90.0, n)) * exp_env(n, 0.06, 0.001)
    mix_into(buf, thud, 0.19, 0.35)
    return buf


# 函数名到构建函数的映射（SFX_SPEC 里留 None 占位，这里一次性绑定，避免上面元组里
# 反复出现函数对象、也方便单独改某一类音色）
_SFX_BUILDERS = {
    "step_grass": s_step_grass, "step_dirt": s_step_dirt, "step_wood": s_step_wood,
    "hoe": s_hoe, "water": s_water, "plant": s_plant, "milk": s_milk, "egg": s_egg,
    "shears": s_shears, "coin": s_coin, "ui_open": s_ui_open, "ui_close": s_ui_close,
    "ui_click": s_ui_click, "animal_cow": s_animal_cow, "animal_goat": s_animal_goat,
    "animal_sheep": s_animal_sheep, "animal_alpaca": s_animal_alpaca,
    "animal_pig": s_animal_pig, "animal_chicken": s_animal_chicken,
    "animal_duck": s_animal_duck, "animal_turkey": s_animal_turkey,
    "animal_bee": s_animal_bee, "build_place": s_build_place,
    "build_done": s_build_done, "save": s_save, "eat": s_eat, "craft": s_craft,
}


def make_sfx(name, dur, seed):
    """生成一个 SFX：固定长度 -> 尾部 10ms 淡出 -> 峰值归一化 -6dBFS。"""
    n = n_of(dur)
    rng = np.random.default_rng(seed)
    sig = _SFX_BUILDERS[name](n, rng)
    sig = np.asarray(sig, dtype=np.float64)
    if len(sig) < n:
        sig = np.pad(sig, (0, n - len(sig)))
    else:
        sig = sig[:n].copy()
    sig = dc_block(sig, 22.0)      # 去掉方波占空比带来的 DC，避免峰值余量被浪费
    sig = fade_out(sig, 0.010)
    sig = normalize_peak(sig, -6.0)
    if not np.all(np.isfinite(sig)):
        raise ValueError("%s 合成出 NaN/Inf" % name)
    return sig


# ------------------------------------------------------- 环形噪声/环境音工具 ----

def periodic_noise(n, rng, slope=0.7, lo=120.0, hi=8000.0):
    """生成**周期恰好为 n 个样本**的带限噪声：随机相位 + 频谱幅度整形 + irfft。

    为什么不用「白噪声 + 低通」：白噪声截成 4.0s 后首尾没有关系，循环时会在接缝
    处跳变（爆音）；而 FFT 生成的信号在数学上就是 n 周期信号，天然无缝。
    slope 控制频谱斜率：越大越「闷」（雨声底噪），越小越「嘶」。
    信号归一化到峰值 1，方便按层叠混音。
    """
    m = n
    nf = m // 2 + 1
    spec = (rng.standard_normal(nf) + 1j * rng.standard_normal(nf))
    freqs = np.fft.rfftfreq(m, 1.0 / SR)
    mag = np.zeros(nf, dtype=np.float64)
    band = (freqs >= lo) & (freqs <= hi)
    if np.any(band):
        mag[band] = (freqs[band] / lo) ** (-slope)
    spec = spec / (np.abs(spec) + 1e-12) * mag
    out = np.fft.irfft(spec, m)
    out -= out.mean()
    peak = float(np.max(np.abs(out)))
    if peak <= 1e-12:
        return np.zeros(m)
    return out / peak


def water_drop(rng, dur=None):
    """一颗水滴：正弦向上滑 + 二次泛音，短衰减。用于雨声里的「滴答」点缀。"""
    if dur is None:
        dur = 0.04 + rng.random() * 0.08
    f0 = 700.0 + rng.random() * 1500.0
    f1 = f0 * (0.6 + 0.5 * rng.random())
    n = n_of(dur)
    f = np.linspace(f0, f1, n)
    sig = sine(phase_of(f, n)) + 0.35 * sine(phase_of(f * 2.0, n))
    return sig * exp_env(n, dur * 0.35, 0.001)


def rain_texture(n, rng, drops_per_sec=11.0, stereo=False):
    """雨声纹理。低频「沙沙」底噪 + 中频「嘶」+ 随机水滴，全部环形叠加/周期生成。

    这个纹理被 rain_loop（单声道 4s）和 bgm_rain 的雨层（立体声 24s）共用：
      * 底噪是严格周期的，循环接缝无跳变；
      * 水滴用 add_circular 绕回开头，尾巴不会在结尾被截断成静音；
      * 慢速起伏 LFO 的频率取「整数个周期/段长」，保证循环处包络也连续。
    """
    base = periodic_noise(n, rng, slope=0.85, lo=120.0, hi=8000.0)
    hiss = periodic_noise(n, rng, slope=0.45, lo=900.0, hi=12000.0)
    tt = np.arange(n) / SR
    dur = n / SR
    # 0.5Hz 起伏，段长 4s/24s 里正好整数个周期（2 圈 / 12 圈）
    lfo = 1.0 + 0.05 * np.sin(2.0 * np.pi * 0.5 * tt)
    mono = (0.85 * base + 0.30 * hiss) * lfo
    if stereo:
        base2 = periodic_noise(n, rng, slope=0.85, lo=120.0, hi=8000.0)
        hiss2 = periodic_noise(n, rng, slope=0.45, lo=900.0, hi=12000.0)
        right = (0.85 * base2 + 0.30 * hiss2) * lfo
        left = mono
        # 左右各自加自己的水滴，做成轻微去相关，听感更宽（不做复杂混响）
        for ch in (left, right):
            for _ in range(int(round(dur * drops_per_sec))):
                pos = rng.random()
                add_circular(ch, water_drop(rng), int(pos * n))
        return left, right
    for _ in range(int(round(dur * drops_per_sec))):
        pos = rng.random()
        add_circular(mono, water_drop(rng), int(pos * n))
    return mono


def make_rain_loop():
    """4.0s 雨声环境音：单声道、峰值约 -9dBFS（环境音比 SFX 轻一点，不抢操作音）。"""
    dur = 4.0
    n = n_of(dur)
    rng = np.random.default_rng(1501)
    sig = rain_texture(n, rng, drops_per_sec=11.0, stereo=False)
    sig = normalize_peak(sig, -9.0)
    if not np.all(np.isfinite(sig)):
        raise ValueError("rain_loop 合成出 NaN/Inf")
    return sig


# ------------------------------------------------------------ BGM 音序器 ----

# 音阶：数字是相对主音的半音数。大调/自然小调够用了，7 首曲子靠和弦进行区分情绪。
SCALES = {
    "major": (0, 2, 4, 5, 7, 9, 11),
    "minor": (0, 2, 3, 5, 7, 8, 10),
}

# 和弦音序号 -> 相对和弦根音的音阶级数：0=根 1=三 2=五 3=八度。
# 旋律音型只用这几个音级就能保证「怎么写都不跑调」。
CHORD_TONE = (0, 2, 4, 7)

# 旋律音型表：(和弦音序号, 时值/16分音符)。全部正好 16 个 16 分音符 = 1 小节。
# 为什么不每首写一份长数组：音型是可复用的「乐句模板」，7 首曲子只需要选模板 +
# 换调性/和弦进行，代码就不会变成 7 份互相拷贝的长数组。
MOTIFS = {
    "skippy": ((0, 2), (1, 2), (2, 2), (3, 2), (2, 2), (1, 2), (0, 2), (3, 2)),
    "walk":   ((0, 4), (1, 2), (2, 2), (1, 2), (0, 2), (3, 4)),
    "calm":   ((0, 8), (2, 4), (3, 4)),
    "sparse": ((2, 8), (-1, 4), (0, 4)),
    "bell":   ((3, 4), (-1, 4), (0, 8)),
    "call":   ((0, 3), (1, 3), (2, 2), (3, 4), (-1, 4)),
}

# 琶音模板：循环取和弦音。morning 的「方波琶音」就靠 up 16 分音符铺底。
ARP_PATTERNS = {
    "up":     (0, 1, 2, 3),
    "updown": (0, 1, 2, 3, 2, 1),
    "broken": (0, 2, 1, 3, 0, 2, 3, 1),
}

# 低音模板：(起始 16 分格, 时值 16 分, 和弦音序号)。
BASS_PATTERNS = {
    "pulse": ((0, 2, 0), (2, 2, 0), (4, 2, 2), (6, 2, 0),
              (8, 2, 0), (10, 2, 2), (12, 2, 0), (14, 2, 0)),
    "half":  ((0, 8, 0), (8, 8, 2)),
    "long":  ((0, 16, 0),),
    "walk":  ((0, 4, 0), (4, 4, 2), (8, 4, 3), (12, 4, 2)),
}

# 鼓型：16 个 16 分格，k=底鼓 s=军鼓 h=踩镲 .=空。用字符串写鼓型比数组直观太多，
# 改节奏时一眼就能看出「第几拍有军鼓」。注意每个字符串必须正好 16 个字符。
DRUM_PATTERNS = {
    "light":   "k.h.s.h.k.h.s.h.",
    "steady":  "k.h.s.h.k.h.s.hh",
    "soft":    "k.......s...h...",
    "sparse":  "k...........h...",
    "rainfew": "k.......s.h.....",
    "snow":    "k...h...s...h...",
    "indoor":  "k.....h.s.....h.",
}
for _pat_name, _pat in DRUM_PATTERNS.items():
    assert len(_pat) == 16, "鼓型 %s 长度 %d，必须 16" % (_pat_name, len(_pat))


def scale_midi(root_midi, scale, degree):
    """音阶级数 -> MIDI。支持负数/超过 7 的级数（自动跨八度），这样和弦转位和低音
    只需要写下移一个八度，不用另写一套音高表。"""
    inv = degree % 7
    octv = degree // 7
    return root_midi + scale[inv] + 12 * octv


def chord_tone_midi(root_midi, scale, chord_root_degree, tone_idx, octave_shift=0):
    """取某个和弦的第 tone_idx 个和弦音（0根/1三/2五/3八度）的 MIDI 号。"""
    return scale_midi(root_midi, scale, chord_root_degree + CHORD_TONE[tone_idx]) + 12 * octave_shift


def pan_gains(pan):
    """等功率声像：pan=-1 全左、+1 全右。用等功率而不是线性，声像移动时总响度不变。"""
    theta = (float(np.clip(pan, -1.0, 1.0)) + 1.0) * math.pi / 4.0
    return math.cos(theta), math.sin(theta)


def lead_note(midi, dur, style, duty, amp, vibrato=0.0):
    """BGM 主旋律音。三种奏法：
      pluck  ：短促衰减，像拨弦/木琴（morning 的琶音、rain 的旋律）
      sustain：四段包络，长音（day/dusk 的持续旋律）
      bell   ：三角波 + 八度正弦、长衰减（night/snow 的空灵钟琴）
      soft   ：三角波为主、慢起音（indoor 的柔和感）
    vibrato 是相对频率的颤音深度，长音加一点会更「有人味」。
    """
    n = n_of(dur)
    if n < 8:
        return np.zeros(max(n, 1))
    f = midi_hz(midi)
    if vibrato:
        rate = 5.2
        f_curve = f * (1.0 + vibrato * np.sin(2.0 * np.pi * rate * np.arange(n) / SR))
    else:
        f_curve = f
    ph = phase_of(f_curve, n)

    if style == "pluck":
        env = exp_env(n, max(0.05, min(0.28, dur * 0.55)), 0.003)
        sig = osc("square", ph, duty)
    elif style == "bell":
        env = exp_env(n, max(0.10, dur * 0.75), 0.002)
        sig = 0.72 * osc("triangle", ph) + 0.28 * osc("sine", ph * 2.0)
    elif style == "soft":
        env = adsr(n, 0.030, min(0.15, dur * 0.30), 0.70, min(0.12, dur * 0.35), 1.2)
        sig = 0.60 * osc("triangle", ph) + 0.40 * osc("sine", ph)
    else:  # sustain
        env = adsr(n, 0.015, min(0.12, dur * 0.25), 0.68, min(0.10, dur * 0.30), 1.3)
        sig = osc("square", ph, duty)
    return sig * env * amp


def arp_note(midi, dur, duty, amp):
    """琶音音：短拨弦，衰减比主旋律更快，避免铺底糊成一片。"""
    n = n_of(dur)
    f = midi_hz(midi)
    ph = phase_of(f, n)
    env = exp_env(n, max(0.03, min(0.25, dur * 0.55)), 0.002)
    return osc("square", ph, duty) * env * amp


def bass_note_g(midi, dur, amp, sustain):
    """低音：三角波。纯三角波低频在小喇叭上不容易听见，所以 sustain 模式保持长音、
    用包络的占空感撑住低音声部，而不是靠加高频谐波（那样会糊）。"""
    n = n_of(dur)
    f = midi_hz(midi)
    ph = phase_of(f, n)
    if sustain:
        env = adsr(n, 0.020, min(0.20, dur * 0.30), 0.85, min(0.06, dur * 0.20), 1.2)
    else:
        env = exp_env(n, max(0.04, min(0.50, dur * 0.80)), 0.003)
    return osc("triangle", ph) * env * amp


def pad_note_g(midi, dur, amp):
    """和声垫：三角波 + 轻微失谐的第二层（1.004 倍频率），做出廉价合成器的合唱感。"""
    n = n_of(dur)
    f = midi_hz(midi)
    ph = phase_of(f, n)
    ph2 = phase_of(f * 1.004, n)
    env = adsr(n, min(0.40, dur * 0.30), min(0.25, dur * 0.20), 0.75,
               min(0.50, dur * 0.30), 1.2)
    return (0.65 * osc("triangle", ph) + 0.35 * osc("sine", ph2)) * env * amp


def drum_hit(kind, rng):
    """鼓：底鼓=正弦扫频（130→48Hz），军鼓=低通噪声+一点鼓腔音，踩镲=高通噪声。"""
    if kind == "k":
        n = n_of(0.18)
        tt = np.arange(n) / SR
        f = 48.0 + 82.0 * np.exp(-tt * 28.0)
        body = sine(phase_of(f, n)) * exp_env(n, 0.10, 0.001)
        click = highpass(noise(n, rng), 1500.0) * exp_env(n, 0.006, 0.0004)
        return body + 0.25 * click
    if kind == "s":
        n = n_of(0.13)
        sn = lowpass(noise(n, rng), 3200.0) * exp_env(n, 0.055, 0.001)
        body = sine(phase_of(190.0, n)) * exp_env(n, 0.045, 0.001)
        return 0.8 * sn + 0.5 * body
    # h
    n = n_of(0.045)
    return highpass(noise(n, rng), 6500.0) * exp_env(n, 0.012, 0.0003)


def circular_echo(x, delay_sec, mix=0.30, taps=(1.0, 0.5, 0.25)):
    """环形多抽头回声：用 np.roll 平移缓冲，等效于在周期信号上做延迟，所以循环
    接缝依然连续。night/snow 的「长混响感」就靠这个，不引入真正的卷积混响。"""
    d = max(1, int(round(delay_sec * SR)))
    out = np.asarray(x, dtype=np.float64).copy()
    for i, decay in enumerate(taps, 1):
        out += (mix * decay) * np.roll(out, i * d)
    return out


# BGM 参数表：每首一行，字段含义：
#   dur   —— 契约时长（秒），决定循环长度和整小节数
#   bpm   —— 设计意图速度（实际速度会取整到「整小节 = 该时长」，见 build_bgm 注释）
#   root  —— 主音 MIDI 号；mode —— 大调/小调
#   prog  —— 和弦进行（音阶级数，按小节循环）
#   lead / arp / bass / pad / drums —— 声部开关与音色参数；None 表示该声部不出现
#   echo  —— 环形回声参数；rain —— 背景雨声层强度
BGM_SPEC = (
    dict(id="bgm_morning", dur=24.0, bpm=104, root=60, mode="major", seed=2101,
         prog=(0, 4, 5, 3),
         lead=dict(motif="skippy", gate="1101", octave=1, duty=0.25, style="pluck",
                   amp=0.22, pan=0.10, vibrato=0.002),
         arp=dict(pattern="up", every=1, octave=2, duty=0.125, amp=0.24, pan=0.18),
         bass=dict(pattern="pulse", octave=-1, amp=0.30, pan=-0.10, sustain=False),
         pad=None,
         drums=dict(pattern="light", amp=0.26, pan=0.0),
         echo=None, rain=0.0),

    dict(id="bgm_day", dur=24.0, bpm=92, root=55, mode="major", seed=2102,
         prog=(0, 3, 5, 4),
         lead=dict(motif="walk", gate="1111", octave=1, duty=0.5, style="sustain",
                   amp=0.26, pan=0.08, vibrato=0.0025),
         arp=dict(pattern="updown", every=2, octave=1, duty=0.25, amp=0.14, pan=0.16),
         bass=dict(pattern="pulse", octave=-1, amp=0.30, pan=-0.10, sustain=False),
         pad=None,
         drums=dict(pattern="steady", amp=0.26, pan=0.0),
         echo=None, rain=0.0),

    dict(id="bgm_dusk", dur=24.0, bpm=76, root=57, mode="minor", seed=2103,
         prog=(0, 5, 2, 6),
         lead=dict(motif="calm", gate="1111", octave=1, duty=0.5, style="soft",
                   amp=0.24, pan=0.08, vibrato=0.004),
         arp=None,
         bass=dict(pattern="half", octave=-1, amp=0.24, pan=-0.10, sustain=True),
         pad=dict(octave=0, amp=0.15, pan=-0.18),
         drums=dict(pattern="soft", amp=0.16, pan=0.0),
         echo=dict(delay=0.30, mix=0.20), rain=0.0),

    dict(id="bgm_night", dur=28.0, bpm=68, root=57, mode="minor", seed=2104,
         prog=(0, 5, 2, 6),
         lead=dict(motif="sparse", gate="1001", octave=2, duty=0.5, style="bell",
                   amp=0.22, pan=0.12, vibrato=0.003),
         arp=None,
         bass=dict(pattern="long", octave=-1, amp=0.22, pan=-0.10, sustain=True),
         pad=dict(octave=0, amp=0.14, pan=-0.18),
         drums=dict(pattern="sparse", amp=0.12, pan=0.0),
         echo=dict(delay=0.33, mix=0.32), rain=0.0),

    dict(id="bgm_rain", dur=24.0, bpm=80, root=50, mode="minor", seed=2105,
         prog=(0, 3, 5, 6),
         lead=dict(motif="call", gate="1111", octave=1, duty=0.25, style="pluck",
                   amp=0.20, pan=0.10, vibrato=0.003),
         arp=None,
         bass=dict(pattern="half", octave=-1, amp=0.26, pan=-0.10, sustain=True),
         pad=dict(octave=0, amp=0.12, pan=-0.18),
         drums=dict(pattern="rainfew", amp=0.15, pan=0.0),
         echo=dict(delay=0.28, mix=0.18), rain=0.22),

    dict(id="bgm_snow", dur=24.0, bpm=72, root=62, mode="major", seed=2106,
         prog=(0, 4, 3, 4),
         lead=dict(motif="bell", gate="1011", octave=2, duty=0.5, style="bell",
                   amp=0.20, pan=0.12, vibrato=0.002),
         arp=dict(pattern="updown", every=2, octave=2, duty=0.5, amp=0.12, pan=0.20),
         bass=dict(pattern="long", octave=-1, amp=0.20, pan=-0.10, sustain=True),
         pad=dict(octave=0, amp=0.10, pan=-0.18),
         drums=dict(pattern="snow", amp=0.13, pan=0.0),
         echo=dict(delay=0.34, mix=0.22), rain=0.0),

    dict(id="bgm_indoor", dur=24.0, bpm=84, root=53, mode="major", seed=2107,
         prog=(0, 3, 0, 4),
         lead=dict(motif="calm", gate="1111", octave=1, duty=0.5, style="soft",
                   amp=0.18, pan=0.06, vibrato=0.003),
         arp=None,
         bass=dict(pattern="half", octave=-1, amp=0.20, pan=-0.10, sustain=True),
         pad=dict(octave=0, amp=0.16, pan=-0.18),
         drums=dict(pattern="indoor", amp=0.12, pan=0.0),
         echo=dict(delay=0.20, mix=0.12), rain=0.0),
)


def build_bgm(cfg):
    """把一首 BGM 合成成 (L, R) 立体声浮点缓冲，长度严格等于契约时长。

    循环长度与 BPM 的取舍：
      契约把时长钉死为 24s/28s，但 104BPM 的 24s 不是整数小节（10.4 小节）。
      如果硬按 104BPM 铺 41.6 拍，循环点会落在小节中间，鼓和和弦都会「跳」。
      所以这里取「离设计 BPM 最近的整小节数」，把实际速度微调成
      bpm_real = bars*4*60/dur（误差 < 8%），保证整段正好是整数小节、循环点落在
      小节线上。听感上 104→100BPM 几乎察觉不到，但接缝会干净很多。
    """
    dur = float(cfg["dur"])
    n = n_of(dur)
    bars = max(1, int(round(dur * cfg["bpm"] / 60.0 / 4.0)))
    step16_sec = dur / (bars * 16)             # 一个 16 分音符的秒数
    bar_sec = step16_sec * 16
    bpm_real = bars * 4 * 60.0 / dur
    scale = SCALES[cfg["mode"]]
    root = cfg["root"]
    prog = cfg["prog"]
    rng = np.random.default_rng(cfg["seed"])

    # 每个声部先各自一个整段环形缓冲，最后再按 pan 混到左右声道。
    # 这样 echo/声像只作用于对应声部，不会被别的声部带偏。
    voice_names = ("lead", "arp", "bass", "pad", "drums")
    voices = {name: np.zeros(n) for name in voice_names}

    def sec_of_step(step_idx):
        return step_idx * step16_sec

    for bar in range(bars):
        chord_root = prog[bar % len(prog)]
        bar_step0 = bar * 16

        # ---- 主旋律：按小节 gate 决定这一小节是否演奏（night 留空拍用）----
        lead = cfg["lead"]
        if lead:
            gate = lead["gate"][bar % len(lead["gate"])]
            if gate == "1":
                step = 0
                for tone_idx, steps in MOTIFS[lead["motif"]]:
                    if step >= 16:
                        break
                    if tone_idx >= 0:
                        midi = chord_tone_midi(root, scale, chord_root, tone_idx,
                                               lead["octave"])
                        note_dur = steps * step16_sec
                        sig = lead_note(midi, note_dur * 0.98, lead["style"],
                                        lead["duty"], lead["amp"], lead["vibrato"])
                        add_circular(voices["lead"], sig,
                                     int(round(sec_of_step(bar_step0 + step) * SR)))
                    step += steps

        # ---- 琶音：按模板循环取和弦音 ----
        arp = cfg["arp"]
        if arp:
            pat = ARP_PATTERNS[arp["pattern"]]
            every = max(1, int(arp["every"]))
            idx = 0
            step = 0
            while step < 16:
                tone_idx = pat[idx % len(pat)]
                midi = chord_tone_midi(root, scale, chord_root, tone_idx, arp["octave"])
                sig = arp_note(midi, every * step16_sec * 0.92, arp["duty"], arp["amp"])
                add_circular(voices["arp"], sig,
                             int(round(sec_of_step(bar_step0 + step) * SR)))
                step += every
                idx += 1

        # ---- 低音：模板决定节奏和和弦音 ----
        bass = cfg["bass"]
        if bass:
            for st, dur_steps, tone_idx in BASS_PATTERNS[bass["pattern"]]:
                midi = chord_tone_midi(root, scale, chord_root, tone_idx, bass["octave"])
                note_dur = dur_steps * step16_sec
                sig = bass_note_g(midi, note_dur * 0.96, bass["amp"], bass["sustain"])
                add_circular(voices["bass"], sig,
                             int(round(sec_of_step(bar_step0 + st) * SR)))

        # ---- 和声垫：每小节三个和弦音铺满 ----
        pad = cfg["pad"]
        if pad:
            for tone_idx in (0, 1, 2):
                midi = chord_tone_midi(root, scale, chord_root, tone_idx, pad["octave"])
                sig = pad_note_g(midi, bar_sec * 0.98, pad["amp"] / 3.0)
                add_circular(voices["pad"], sig,
                             int(round(sec_of_step(bar_step0) * SR)))

        # ---- 鼓：16 格字符串逐格检查 ----
        drums = cfg["drums"]
        if drums:
            pat = DRUM_PATTERNS[drums["pattern"]]
            for i, ch in enumerate(pat):
                if ch in "ksh":
                    hit = drum_hit(ch, rng) * drums["amp"]
                    add_circular(voices["drums"], hit,
                                 int(round(sec_of_step(bar_step0 + i) * SR)))

    # ---- 声部混音：echo -> pan -> 左右声道 ----
    left = np.zeros(n)
    right = np.zeros(n)
    pan_by_voice = {
        "lead": cfg["lead"]["pan"] if cfg["lead"] else 0.0,
        "arp": cfg["arp"]["pan"] if cfg["arp"] else 0.0,
        "bass": cfg["bass"]["pan"] if cfg["bass"] else 0.0,
        "pad": cfg["pad"]["pan"] if cfg["pad"] else 0.0,
        "drums": cfg["drums"]["pan"] if cfg["drums"] else 0.0,
    }
    for name in voice_names:
        buf = voices[name]
        if cfg["echo"] and name in ("lead", "pad"):
            buf = circular_echo(buf, cfg["echo"]["delay"], cfg["echo"]["mix"])
        gl, gr = pan_gains(pan_by_voice[name])
        left += buf * gl
        right += buf * gr

    # ---- 雨层（只有 bgm_rain）：独立立体声纹理，轻微铺底 ----
    if cfg["rain"] > 0.0:
        rain_l, rain_r = rain_texture(n, rng, drops_per_sec=8.0, stereo=True)
        left += rain_l * cfg["rain"]
        right += rain_r * cfg["rain"]

    # ---- 去直流：占空比 0.125/0.25 的方波声部会带来 DC，减均值即可（常量不破坏
    #      周期性，循环接缝不受影响），同时把峰值余量留给真正的声音 ----
    left -= left.mean()
    right -= right.mean()

    # ---- 统一峰值归一化到 -12dBFS（所有曲子同一标准，游戏里靠 AudioManager 调音量）----
    peak = max(float(np.max(np.abs(left))), float(np.max(np.abs(right))))
    if peak <= 1e-12:
        raise ValueError("%s 混音为空" % cfg["id"])
    scale_to = db_to_amp(-12.0) / peak
    left *= scale_to
    right *= scale_to

    if not (np.all(np.isfinite(left)) and np.all(np.isfinite(right))):
        raise ValueError("%s 合成出 NaN/Inf" % cfg["id"])
    return left, right, dict(bars=bars, bpm_real=bpm_real)


# ---------------------------------------------------------------- 写 WAV ----

def to_int16(sig):
    """浮点 [-1,1] -> int16。先 clip 再取整，防止归一化后的过冲把波形削平。"""
    x = np.asarray(sig, dtype=np.float64) * 32767.0
    return np.clip(np.rint(x), -32768, 32767).astype("<i2")


def write_wav_mono(path, sig):
    ints = to_int16(sig)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(ints.tobytes())
    return len(ints) * 2


def write_wav_stereo(path, left, right):
    inter = np.empty(len(left) * 2, dtype=np.float64)
    inter[0::2] = left
    inter[1::2] = right
    ints = to_int16(inter)
    with wave.open(path, "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(ints.tobytes())
    return len(ints) * 2


# ---------------------------------------------------------------- 自检 ----

def inspect_wav(path, expect_channels, loop=False):
    """重新打开刚写出的文件做独立校验（不是信任内存里的数组）：
    采样率/位深/声道数/帧数、峰值 dBFS、以及循环文件的首尾接缝与尾部能量。"""
    with wave.open(path, "rb") as w:
        ch = w.getnchannels()
        sw = w.getsampwidth()
        fr = w.getframerate()
        nf = w.getnframes()
        raw = w.readframes(nf)
    data = np.frombuffer(raw, dtype="<i2").astype(np.float64) / 32768.0
    if ch == 2:
        data = data.reshape(-1, 2)
    peak = float(np.max(np.abs(data))) if len(data) else 0.0
    peak_db = 20.0 * math.log10(max(peak, 1e-9))
    info = dict(path=path, channels=ch, sampwidth=sw, framerate=fr, frames=nf,
                seconds=nf / float(SR), peak_db=peak_db,
                size=os.path.getsize(path))
    # 「静音尾巴」判定：从末尾往前数连续低于 -60dBFS 的样本。SFX 只要求别把后半段
    # 写空；循环音乐则要求接缝附近仍有声音（可落在休止符上，但不能真空一段）。
    mono_abs = np.max(np.abs(data), axis=1) if ch == 2 else np.abs(data)
    thr = 1e-3
    i = len(mono_abs) - 1
    while i >= 0 and mono_abs[i] < thr:
        i -= 1
    info["trail_run"] = len(mono_abs) - 1 - i
    if loop:
        tail = int(round(0.020 * SR))
        if ch == 2:
            diffs = []
            tail_rms = []
            for c in range(2):
                x = data[:, c]
                diffs.append(abs(float(x[-1] - x[0])))
                tail_rms.append(float(np.sqrt(np.mean(x[-tail:] ** 2))))
            info["seam"] = max(diffs)
            info["max_adj"] = float(max(np.max(np.abs(np.diff(data[:, c]))) for c in range(2)))
            info["tail_rms"] = max(tail_rms)
            info["rms"] = float(np.sqrt(np.mean(data ** 2)))
        else:
            x = data
            info["seam"] = abs(float(x[-1] - x[0]))
            info["max_adj"] = float(np.max(np.abs(np.diff(x)))) if len(x) > 1 else 0.0
            info["tail_rms"] = float(np.sqrt(np.mean(x[-tail:] ** 2)))
            info["rms"] = float(np.sqrt(np.mean(data ** 2)))
        info["seam_ok"] = info["seam"] <= info["max_adj"] * 1.05 + 1e-12
    return info


def print_file_line(tag, info):
    extra = ""
    if "seam" in info:
        extra = "  seam=%.5f max_adj=%.5f tail_rms=%.4f trail=%.0fms %s" % (
            info["seam"], info["max_adj"], info["tail_rms"],
            info["trail_run"] * 1000.0 / SR,
            "OK" if info["seam_ok"] else "FAIL")
    else:
        extra = "  tail=%.0fms" % (info["trail_run"] * 1000.0 / SR)
    print("  %-16s %-7s %7.3fs  %7.2f dBFS  %8.1f KB%s" % (
        os.path.basename(info["path"]), tag, info["seconds"], info["peak_db"],
        info["size"] / 1024.0, extra))


# ---------------------------------------------------------------- 主流程 ----

def main():
    try:
        sys.stdout.reconfigure(encoding="utf-8")
    except Exception:
        pass
    os.makedirs(SFX_DIR, exist_ok=True)
    os.makedirs(BGM_DIR, exist_ok=True)

    print("=== 《小牧场日记》程序化音频生成 ===")
    print("采样率 %d Hz / 16-bit PCM / 固定随机种子（重复运行字节一致）" % SR)
    print("输出根目录: %s" % os.path.join(ROOT, "audio"))
    print()

    sfx_infos = []
    print("[1/3] 单声道 SFX（27 个）")
    for name, dur, _fn, seed in SFX_SPEC:
        sig = make_sfx(name, dur, seed)
        path = os.path.join(SFX_DIR, name + ".wav")
        write_wav_mono(path, sig)
        sfx_infos.append(inspect_wav(path, 1, loop=False))
        print_file_line("mono", sfx_infos[-1])

    print()
    print("[2/3] 环境音 rain_loop（4.0s 单声道无缝循环）")
    rain = make_rain_loop()
    rain_path = os.path.join(SFX_DIR, "rain_loop.wav")
    write_wav_mono(rain_path, rain)
    rain_info = inspect_wav(rain_path, 1, loop=True)
    print_file_line("mono", rain_info)

    bgm_infos = []
    print()
    print("[3/3] BGM（7 首立体声无缝循环）")
    bgm_meta = {}
    for cfg in BGM_SPEC:
        left, right, meta = build_bgm(cfg)
        path = os.path.join(BGM_DIR, cfg["id"] + ".wav")
        write_wav_stereo(path, left, right)
        info = inspect_wav(path, 2, loop=True)
        bgm_infos.append(info)
        bgm_meta[cfg["id"]] = meta
        print_file_line("stereo", info)
        print("  %-16s 实际速度 %.2f BPM / %d 小节（设计 %.0f BPM，取整到整小节）" % (
            "", meta["bpm_real"], meta["bars"], cfg["bpm"]))

    # ---------------- 汇总自检 ----------------
    print()
    print("=== 自检汇总 ===")
    problems = []

    all_infos = sfx_infos + [rain_info] + bgm_infos

    def check_common(info):
        base = os.path.basename(info["path"])
        if info["sampwidth"] != 2:
            problems.append("%s 位深不是 16-bit" % base)
        if info["framerate"] != SR:
            problems.append("%s 采样率不是 44100" % base)
        if info["channels"] != 2 and "bgm" in base:
            problems.append("%s 不是立体声" % base)
        if info["channels"] != 1 and "bgm" not in base:
            problems.append("%s 不是单声道" % base)

    # 时长必须和契约完全一致（按样本数核对，避免 1 样本误差）
    expect = {name: dur for name, dur, _fn, _seed in SFX_SPEC}
    expect["rain_loop"] = 4.0
    for cfg in BGM_SPEC:
        expect[cfg["id"]] = cfg["dur"]
    for info in all_infos:
        base = os.path.splitext(os.path.basename(info["path"]))[0]
        check_common(info)
        want_frames = n_of(expect[base])
        if info["frames"] != want_frames:
            problems.append("%s 帧数 %d != 期望 %d" % (base, info["frames"], want_frames))
        if "seam" in info and not info["seam_ok"]:
            problems.append("%s 循环接缝过大 (seam=%.5f > max_adj=%.5f)" % (
                base, info["seam"], info["max_adj"]))
        if "seam" in info:
            if info["trail_run"] > int(0.05 * SR):
                problems.append("%s 循环尾部有 %.0fms 静音（应 <50ms）" % (
                    base, info["trail_run"] * 1000.0 / SR))
            if info["tail_rms"] < info["rms"] * 0.03:
                problems.append("%s 尾部能量过低（疑似静音尾巴）" % base)
        elif info["trail_run"] > int(0.35 * info["frames"]):
            problems.append("%s 后半段接近静音（trail=%.0fms / %.0fms）" % (
                base, info["trail_run"] * 1000.0 / SR, info["seconds"] * 1000.0))
        if not np.isfinite(info["peak_db"]):
            problems.append("%s 峰值不是有限数" % base)

    # 峰值范围
    for info in sfx_infos:
        if abs(info["peak_db"] + 6.0) > 0.15:
            problems.append("%s 峰值 %.2f dBFS 偏离 -6dBFS" % (
                os.path.basename(info["path"]), info["peak_db"]))
    if abs(rain_info["peak_db"] + 9.0) > 0.15:
        problems.append("rain_loop 峰值 %.2f dBFS 偏离 -9dBFS" % rain_info["peak_db"])
    for info in bgm_infos:
        if abs(info["peak_db"] + 12.0) > 0.15:
            problems.append("%s 峰值 %.2f dBFS 偏离 -12dBFS" % (
                os.path.basename(info["path"]), info["peak_db"]))

    # 按类别统计
    sfx_count = len(sfx_infos)
    bgm_count = len(bgm_infos)
    sfx_size = sum(i["size"] for i in sfx_infos) + rain_info["size"]
    bgm_size = sum(i["size"] for i in bgm_infos)
    total_size = sfx_size + bgm_size
    sfx_seconds = [i["seconds"] for i in sfx_infos]
    bgm_seconds = [i["seconds"] for i in bgm_infos]

    print("文件数：SFX %d（含 rain_loop）+ BGM %d = 共 %d 个" % (
        sfx_count + 1, bgm_count, sfx_count + 1 + bgm_count))
    print("SFX 时长范围：%.2fs ~ %.2fs（rain_loop %.2fs）" % (
        min(sfx_seconds), max(sfx_seconds), rain_info["seconds"]))
    print("BGM 时长范围：%.2fs ~ %.2fs（全部整小节，立体声）" % (
        min(bgm_seconds), max(bgm_seconds)))
    print("大小：SFX %.2f MB（%.2f MiB）+ BGM %.2f MB（%.2f MiB）= %.2f MB（%.2f MiB）" % (
        sfx_size / 1e6, sfx_size / 1048576.0,
        bgm_size / 1e6, bgm_size / 1048576.0,
        total_size / 1e6, total_size / 1048576.0))
    print("BGM 循环接缝：seam/max_adj 全部通过；尾部无 50ms 以上静音；无 NaN/Inf")
    print("时长/采样率/位深/声道数：全部与契约一致")

    # 供报告引用的明细
    print()
    print("循环接缝明细（|last-first|，应不超过文件内相邻样本最大差）：")
    for info in [rain_info] + bgm_infos:
        base = os.path.splitext(os.path.basename(info["path"]))[0]
        print("  %-16s seam=%.6f  max_adj=%.6f  ratio=%.4f" % (
            base, info["seam"], info["max_adj"], info["seam"] / max(info["max_adj"], 1e-12)))

    if problems:
        print()
        print("!!! 自检发现问题 %d 项：" % len(problems))
        for p in problems:
            print("  - " + p)
        return 1
    print()
    print("自检结果：全部通过 ✓")
    return 0


if __name__ == "__main__":
    sys.exit(main())

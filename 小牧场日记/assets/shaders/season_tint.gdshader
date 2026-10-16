shader_type canvas_item;
// 季节染色：把画面颜色朝目标色 lerp（GDD §2.1）
//
// 为什么不用 CanvasItem.modulate：modulate 只能「乘」，乘不出白色。
// 冬天的草地 #7FC15E 无论乘多大的系数都只会变成更亮的绿，永远不会变雪白。
// 只有 mix() 才能做「去饱和 → 逼近目标色」，所以这里用一个 4 行的着色器。
//
// 用法：GroundLayer.set_season_tint(season) 会写入 tint / amount 两个 uniform。
//   amount = 0    → 原样（春）
//   amount = 0.8  → 八成染成雪白（冬）

uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float amount : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	// COLOR 进来时已经是「贴图 × 顶点色 × modulate」，就地改 rgb 即可，alpha 不动
	COLOR.rgb = mix(COLOR.rgb, tint.rgb, amount);
}

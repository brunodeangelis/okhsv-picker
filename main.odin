package main

// OKHSV Color Picker in Odin+Raylib+GLSL
// by Bruno De Angelis - https://brunodeangelis.com

// References and resources:
//   - https://bottosson.github.io/posts/colorwrong/
//   - https://bottosson.github.io/posts/colorpicker/
//   - https://bottosson.github.io/misc/ok_color.h
//   - https://hsluv.org/
//   - https://github.com/hsluv/hsluv-c
//   - https://github.com/williammalo/hsluv-glsl/
//   - https://www.shadertoy.com/view/sdK3D1
//   - https://www.shadertoy.com/view/3dByzK
//   - https://odin-lang.org/
//   - https://raylib.com/

import "core:math"

import rl "vendor:raylib"


picked_hue: f32 = 0.5
picked_color: rl.Color
picked_color_pos := rl.Vector2{0.75, 0.25} // top-left 0 -> bottom-right 1

main :: proc() {
	rl.SetConfigFlags({.MSAA_4X_HINT, .VSYNC_HINT})

	rl.InitWindow(400, 255, "OKHSV")
	defer rl.CloseWindow()

	rl.SetTargetFPS(240)

	picker_rec := rl.Rectangle{0, 0, 255, 255}
	picker_texture := texture_from_rec(picker_rec)
	defer rl.UnloadTexture(picker_texture)

	hue_rec := rl.Rectangle{271, 0, 32, 255}
	hue_texture := texture_from_rec(hue_rec)
	defer rl.UnloadTexture(hue_texture)

	shader_bytes := #load("picker.fs", cstring)
	picker_shader := rl.LoadShaderFromMemory(nil, shader_bytes)
	defer rl.UnloadShader(picker_shader)

	shader_bytes = #load("hue.fs", cstring)
	hue_shader := rl.LoadShaderFromMemory(nil, shader_bytes)
	defer rl.UnloadShader(hue_shader)

	picker_loc_uhue := rl.GetShaderLocation(picker_shader, "uHue")

	set_picked_color()

	picking_color: bool
	picking_hue: bool
	for !rl.WindowShouldClose() {
		mouse_pos := rl.GetMousePosition()
		selector_size: f32 = 5

		if rl.IsMouseButtonPressed(.LEFT) {
			if rl.CheckCollisionPointRec(mouse_pos, picker_rec) do picking_color = true
			if rl.CheckCollisionPointRec(mouse_pos, hue_rec) do picking_hue = true
		}

		if picking_hue {
			picked_hue = clamp_eps(mouse_pos.y / hue_rec.height)
			set_picked_color()
			if rl.IsMouseButtonReleased(.LEFT) do picking_hue = false
		}

		if picking_color {
			selector_size = 12
			picked_color_pos = {
				clamp_eps(mouse_pos.x / picker_rec.width),
				clamp_eps(mouse_pos.y / picker_rec.height),
			}
			set_picked_color()
			if rl.IsMouseButtonReleased(.LEFT) do picking_color = false
		}

		rl.SetShaderValue(picker_shader, picker_loc_uhue, &picked_hue, .FLOAT)
		{rl.BeginDrawing()
			rl.ClearBackground(rl.DARKGRAY)

			rl.BeginShaderMode(picker_shader)
			rl.DrawTexture(picker_texture, i32(picker_rec.x), i32(picker_rec.y), rl.WHITE)
			rl.EndShaderMode()

			rl.BeginShaderMode(hue_shader)
			rl.DrawTexture(hue_texture, i32(hue_rec.x), i32(hue_rec.y), rl.WHITE)
			rl.EndShaderMode()

			// Picker indicator/selector
			rl.DrawCircleV(picked_color_pos * picker_rec.width, selector_size * 1.2, rl.BLACK)
			rl.DrawCircleV(picked_color_pos * picker_rec.width, selector_size, picked_color)
			rl.DrawCircleLinesV(picked_color_pos * picker_rec.width, selector_size, rl.WHITE)
			rl.DrawRectangle(i32(hue_rec.x + hue_rec.width + 16), 0, 64, 64, picked_color)

			// Hue indicator/selector
			hue_ind_y := picked_hue * hue_rec.height
			hue_ind_padding: f32 = 2
			hue_ind_space: f32 = 4
			rl.DrawTriangle(
				{hue_rec.x - hue_ind_space - hue_ind_padding, hue_ind_y - hue_ind_space},
				{hue_rec.x - hue_ind_space - hue_ind_padding, hue_ind_y + hue_ind_space},
				{hue_rec.x - hue_ind_padding, hue_ind_y},
				rl.WHITE,
			)
			hue_rightside_indicator_x := hue_rec.x + hue_rec.width
			rl.DrawTriangle(
				{
					hue_rightside_indicator_x + hue_ind_space + hue_ind_padding,
					hue_ind_y + hue_ind_space,
				},
				{
					hue_rightside_indicator_x + hue_ind_space + hue_ind_padding,
					hue_ind_y - hue_ind_space,
				},
				{hue_rightside_indicator_x + hue_ind_padding, hue_ind_y},
				rl.WHITE,
			)
		};rl.EndDrawing()
	}
}

texture_from_rec :: proc(rec: rl.Rectangle) -> rl.Texture2D {
	img := rl.GenImageColor(i32(rec.width), i32(rec.height), rl.BLANK)
	defer rl.UnloadImage(img)
	return rl.LoadTextureFromImage(img)
}

set_picked_color :: proc() {
	rgb := okhsv_to_srgb({picked_hue, picked_color_pos.x, 1 - picked_color_pos.y})
	picked_color = {u8(rgb.r * 255), u8(rgb.g * 255), u8(rgb.b * 255), 255}
}

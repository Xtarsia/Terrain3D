shader_type spatial;

uniform sampler2D height_map;

float uncompressFetch(sampler2D map, ivec2 iuv) {
	ivec2 bc_uv = ivec2((iuv / 4) * 2);
	float px0 = texelFetch(map, bc_uv + ivec2(0,0), 0).r;
	float px1 = texelFetch(map, bc_uv + ivec2(1,0), 0).r;
	uvec2 block_pos = uvec2(iuv) % 4u;
	uint index = block_pos.y * 4u + block_pos.x;
	uint indices = floatBitsToUint(texelFetch(map, bc_uv + ivec2(int(index < 8u), 1), 0).r);
	float idx = float((indices >> (index % 8u * 4u)) & 0xFu) / 15.0;
	return fma(idx, px1 - px0, px0);
}

void vertex() {
	VERTEX.y = uncompressFetch(height_map, ivec2(VERTEX.xz));
}
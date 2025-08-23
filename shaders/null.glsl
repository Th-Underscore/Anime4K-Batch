//!HOOK MAIN
//!BIND HOOKED
//!DESC Null shader (passthrough)

vec4 hook() {
    return HOOKED_tex(HOOKED_pos);
}

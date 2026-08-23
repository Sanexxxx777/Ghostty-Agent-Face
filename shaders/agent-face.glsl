// Ghostty "living face" agent-status background shader — v4.1.
// Signal channel = terminal background color set via OSC 11 (invisible to the eye).
// Visible background is ALWAYS forced back to BASE_BG; only the face changes.
// custom-shader-animation = always   (needed for continuous breathing/blink)
//
// v4  adds: (1) pupils track the terminal cursor (iCurrentCursor, Ghostty >=1.1),
//           (2) night fade 23:00-07:00 via iDate.w, (3) SLEEP state, (4) HELPERS state.
// v4.1 adds:(5) SLEEP aquarium — fish/seaweed/crab/turtle appear when the face falls asleep.
// Uniforms iCurrentCursor / iDate are Ghostty built-ins — NEVER declare them here.

// BASE_BG MUST equal your real Ghostty background-color (default #282c34).
// If you change theme, update this constant.
const vec3 BASE_BG = vec3(41.0, 44.0, 51.0) / 255.0;  // MEASURED on-screen idle bg (profile-transformed #282c34)

float luma(vec3 c){ return dot(c, vec3(0.299, 0.587, 0.114)); }
vec3  darker(vec3 a, vec3 b){ return mix(a, b, step(luma(b), luma(a))); }
float hash21(vec2 p){ p = fract(p * vec2(123.34, 456.21)); p += dot(p, p + 45.32); return fract(p.x * p.y); }
float sdRoundBox(vec2 p, vec2 b, float r){ vec2 d = abs(p) - b + r; return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0) - r; }

// SLEEP "Z" glyph: three strokes (top bar, diagonal, bottom bar) in local [-0.6,0.6] space.
float zGlyph(vec2 p){
    float th  = 0.13;
    float inX = 1.0 - smoothstep(0.5, 0.5 + th, abs(p.x));
    float top = (1.0 - smoothstep(th * 0.6, th, abs(p.y - 0.5))) * inX;
    float bot = (1.0 - smoothstep(th * 0.6, th, abs(p.y + 0.5))) * inX;
    float dln = abs(p.y - p.x) * 0.70710678;                       // distance to diagonal y=x
    float box = inX * (1.0 - smoothstep(0.5, 0.5 + th, abs(p.y)));
    float diag = (1.0 - smoothstep(th * 0.6, th, dln)) * box;
    return max(top, max(bot, diag));
}

// One aquarium fish: coverage 0..1 at screen point fp (Y-up, isotropic).
// Trajectory = Lissajous wander; orientation = analytic derivative; tail wags; eye = hole.
// amp=(A,B,C,D), frq=(w1..w4), pha=(f1..f4) — incommensurate per fish. No loops / no arrays-of-structs.
float fishCov(vec2 fp, vec2 center, vec4 amp, vec4 frq, vec4 pha, float t, float len, float ht, float wagPh, vec2 curFp){
    vec2 pos = center + vec2(amp.x*sin(frq.x*t+pha.x) + amp.y*sin(frq.y*t+pha.y),
                             amp.z*sin(frq.z*t+pha.z) + amp.w*sin(frq.w*t+pha.w));
    vec2 vel = vec2(amp.x*frq.x*cos(frq.x*t+pha.x) + amp.y*frq.y*cos(frq.y*t+pha.y),
                    amp.z*frq.z*cos(frq.z*t+pha.z) + amp.w*frq.w*cos(frq.w*t+pha.w));
    float sp  = length(vel) + 1e-4;
    vec2  dirRaw = vel / sp;
    // side-view aquarium: body near-horizontal, mild pitch; the turn is SMOOTH —
    // fx passes through 0, the body foreshortens (fish briefly faces the viewer), then re-opens
    float fx  = clamp(dirRaw.x / 0.25, -1.0, 1.0);
    float sx  = fx >= 0.0 ? 1.0 : -1.0;
    vec2  dir = normalize(vec2(sx * max(abs(fx), 0.06), dirRaw.y * 0.45));
    float lenEff = len * mix(0.35, 1.0, abs(fx));
    vec2  rp  = pos - curFp;                                        // cursor repulsion (stateless)
    float rd  = length(rp);
    pos += (rp / max(rd, 1e-4)) * (0.02 / (rd + 0.2));
    vec2 dloc = fp - pos;
    vec2 ql = vec2(dir.x*dloc.x + dir.y*dloc.y, -dir.y*dloc.x + dir.x*dloc.y);   // rotate into fish frame (+x forward)
    vec2 e = vec2(ql.x / lenEff, ql.y / ht);
    float body = 1.0 - smoothstep(0.85, 1.05, length(e));          // ellipse body
    float tailLen = lenEff * 0.95;
    float x0 = -lenEff * 0.65;
    float tt = clamp((x0 - ql.x) / tailLen, 0.0, 1.0);             // 0 at body, 1 at tail tip
    float wy = ht * 0.8 * sin(t * (2.0 + 5.0 * sp) + wagPh) * tt;  // wag amplitude ~ speed
    float halfH = mix(0.02 * ht, ht * 1.25, tt);                  // fan widens to tip
    float inX = step(x0 - tailLen, ql.x) * step(ql.x, x0);
    float tail = inX * (1.0 - smoothstep(halfH * 0.6, halfH + 0.004, abs(ql.y - wy)));
    float cov = max(body, tail);
    float eye = 1.0 - smoothstep(ht * 0.16, ht * 0.30, length(ql - vec2(lenEff * 0.45, ht * 0.35)));
    cov *= (1.0 - 0.85 * eye);                                     // dark eye near head-top
    return clamp(cov, 0.0, 1.0);
}

// Seaweed strand growing from the bottom edge (fp is Y-up): swaying tapered ribbon.
// w = base width, leaf = 0 plain ribbon / 1 leafy scalloped edge (slower sway).
float weedCov(vec2 fp, float xb, float h, float ph, float t, float w, float leaf){
    float yr = clamp(fp.y / h, 0.0, 1.0);
    float sway = (0.012 + 0.038 * yr * yr) * sin(t * (0.6 + 0.3 * leaf) + ph + yr * 3.0);
    float xc = xb + sway;
    float hw = w * (1.0 - 0.55 * yr) * (1.0 + 0.45 * leaf * sin(yr * 16.0 + ph * 5.0));
    float band = 1.0 - smoothstep(hw * 0.6, hw + 0.003, abs(fp.x - xc));
    return band * step(fp.y, h);
}

// Crab patrolling the bottom edge, sideways, ping-pong between xmin..xmax.
float crabCov(vec2 fp, float t, float xmin, float xmax){
    float ph  = fract(t * 0.016);
    float tri = 1.0 - abs(ph * 2.0 - 1.0);
    float cx  = mix(xmin, xmax, tri);
    float cy  = 0.030 + 0.004 * abs(sin(t * 5.0));
    vec2  p   = fp - vec2(cx, cy);
    float body = 1.0 - smoothstep(0.85, 1.10, length(vec2(p.x / 0.040, p.y / 0.020)));
    float eyeA = 1.0 - smoothstep(0.004, 0.008, length(p - vec2(-0.012, 0.024)));
    float eyeB = 1.0 - smoothstep(0.004, 0.008, length(p - vec2( 0.012, 0.024)));
    float clwA = 1.0 - smoothstep(0.007, 0.012, length(p - vec2(-0.048, 0.010)));
    float clwB = 1.0 - smoothstep(0.007, 0.012, length(p - vec2( 0.048, 0.010)));
    float legs = (1.0 - smoothstep(0.030, 0.046, abs(p.x)))
               * (1.0 - smoothstep(0.006, 0.012, abs(p.y + 0.022 + 0.004 * sin(t * 9.0 + sign(p.x) * 1.5))));
    return max(body, max(max(eyeA, eyeB), max(max(clwA, clwB), legs)));
}

// Sleeping turtle near the right bottom corner; head peeks out once in a while.
float turtleCov(vec2 fp, float t, float x0){
    vec2  p = fp - vec2(x0, 0.030);
    float shell = (1.0 - smoothstep(0.85, 1.05, length(vec2(p.x / 0.055, p.y / 0.032)))) * step(-0.028, p.y);
    float peek = smoothstep(0.86, 0.93, sin(t * 0.26));
    float hx = -0.055 - 0.020 * peek;
    float head = 1.0 - smoothstep(0.85, 1.10, length(vec2((p.x - hx) / 0.016, (p.y + 0.010) / 0.011)));
    float eye = (1.0 - smoothstep(0.0035, 0.006, length(p - vec2(hx - 0.004, -0.006)))) * peek;
    float cov = max(shell, head * max(peek, 0.35));
    cov *= (1.0 - 0.8 * eye);
    return clamp(cov, 0.0, 1.0);
}

void mainImage(out vec4 fragColor, in vec2 fragCoord){
    vec2 R  = iResolution.xy;
    vec2 uv = fragCoord / R;

    // ---------- 1. sample signal color from darkest corner (avoid text) ----------
    vec3 c0 = texture(iChannel0, vec2(0.03, 0.03)).rgb;
    vec3 c1 = texture(iChannel0, vec2(0.97, 0.03)).rgb;
    vec3 c2 = texture(iChannel0, vec2(0.03, 0.97)).rgb;
    vec3 c3 = texture(iChannel0, vec2(0.97, 0.97)).rgb;
    vec3 bg = darker(darker(c0, c1), darker(c2, c3));

    // ---------- 2. classify: signals are INVISIBLE +5/255 offsets from BASE_BG ----------
    // The background never visibly changes, shader or no shader: the signal is a
    // color delta the eye cannot see, matched here by exact distance.
    // The 8 cube corners of {0,u5}^3 map 1:1 to idle + 7 states.
    // +2/255 offsets: below human perception even on bright wide-gamut displays,
    // still exactly classifiable (texture returns exact 8-bit values).
    float eps  = 0.001;
    // Targets = MEASURED on-screen values (display profile transforms the sent bytes;
    // calibrated {run cal_probe} 19.07). Tight window: full at exact byte match, off at +-1.5.
    float wRun   = 1.0 - smoothstep(0.0028, 0.0058, distance(bg, vec3(43.0, 44.0, 51.0) / 255.0));
    float wWork  = 1.0 - smoothstep(0.0028, 0.0058, distance(bg, vec3(41.0, 47.0, 51.0) / 255.0));
    float wDone  = 1.0 - smoothstep(0.0028, 0.0058, distance(bg, vec3(41.0, 44.0, 54.0) / 255.0));
    float wAttn  = 1.0 - smoothstep(0.0028, 0.0058, distance(bg, vec3(44.0, 47.0, 52.0) / 255.0));
    float wDizzy = 1.0 - smoothstep(0.0028, 0.0058, distance(bg, vec3(43.0, 44.0, 54.0) / 255.0));
    float wSleep = 1.0 - smoothstep(0.0028, 0.0058, distance(bg, vec3(41.0, 47.0, 54.0) / 255.0));
    float wHelp  = 1.0 - smoothstep(0.0028, 0.0058, distance(bg, vec3(44.0, 47.0, 54.0) / 255.0));
    // v6 states: +6/255 single-channel offsets (2x the +3 signals above), added 23.08.
    // Window widened to 0.0035-0.0090 to absorb macOS color-profile rounding we have not
    // individually re-measured on screen (only run/work/done were calibrated by cal_probe);
    // nearest neighbour distance from any v6 target to any v4.1 target is >=0.0118, so the
    // wider window still cannot cross-fire on an existing state.
    float wFail  = 1.0 - smoothstep(0.0035, 0.0090, distance(bg, vec3(47.0, 44.0, 51.0) / 255.0));
    float wTired = 1.0 - smoothstep(0.0035, 0.0090, distance(bg, vec3(41.0, 50.0, 51.0) / 255.0));
    float wSkull = 1.0 - smoothstep(0.0035, 0.0090, distance(bg, vec3(41.0, 44.0, 57.0) / 255.0));
    float wIdle = clamp(1.0 - wRun - wDone - wAttn - wWork - wDizzy - wSleep - wHelp
                             - wFail - wTired - wSkull, 0.0, 1.0);
    float wsum  = wIdle + wRun + wDone + wAttn + wWork + wDizzy + wSleep + wHelp
                + wFail + wTired + wSkull + eps;
    wIdle /= wsum; wRun /= wsum; wDone /= wsum; wAttn /= wsum;
    wWork /= wsum; wDizzy /= wsum; wSleep /= wsum; wHelp /= wsum;
    wFail /= wsum; wTired /= wsum; wSkull /= wsum;
    float signalActive = 1.0 - wIdle;     // 0 in IDLE -> pass-through
    float wWorkV = wWork + wHelp;          // HELPERS renders the WORK face (eyes/mouth/"...")

    // ---------- night fade: 23:00 -> 07:00 local, faceAmp *= 0.55, half-hour ramps ----------
    float hLocal = iDate.w / 3600.0;                                   // hours since local midnight
    float night  = max(smoothstep(23.0, 23.5, hLocal), 1.0 - smoothstep(6.5, 7.0, hLocal));
    float nightMul = mix(1.0, 0.55, night);

    // ---------- 3. per-state colors & morph parameters (blended) ----------
    vec3 cIdle  = vec3(0.45, 0.55, 0.72);
    vec3 cRun   = vec3(0.98, 0.72, 0.22);
    vec3 cDone  = vec3(0.30, 0.95, 0.52);
    vec3 cAttn  = vec3(1.00, 0.42, 0.18);
    vec3 cWork  = vec3(0.95, 0.82, 0.35);
    vec3 cDizzy = vec3(0.72, 0.45, 0.95);
    vec3 cSleep = vec3(0.42, 0.40, 0.68);                              // dim blue-purple
    vec3 cFail  = vec3(0.90, 0.20, 0.22);                              // pained red
    vec3 cTired = vec3(0.38, 0.44, 0.52);                              // dim slate (fatigue)
    vec3 cSkull = vec3(0.78, 0.78, 0.74);                              // pale bone
    vec3 faceCol = wIdle*cIdle + wRun*cRun + wDone*cDone + wAttn*cAttn
                 + wWorkV*cWork + wDizzy*cDizzy + wSleep*cSleep
                 + wFail*cFail + wTired*cTired + wSkull*cSkull;

    float eyeAsp   = wIdle*0.42 + wRun*0.95 + wDone*0.80 + wAttn*1.10 + wWorkV*0.30 + wDizzy*0.95 + wSleep*0.30
                   + wFail*0.60 + wTired*0.55 + wSkull*0.50;
    float arcAmt   = wDone;                                            // eyes -> "^" arcs
    float oAmt     = wAttn;                                            // mouth -> "o"
    float smile    = wDone*0.11;                                       // smile depth
    float mouthW   = wIdle*0.13 + wRun*0.15 + wDone*0.30 + wAttn*0.10 + wWorkV*0.10 + wDizzy*0.20 + wSleep*0.08
                    + wFail*0.18 + wTired*0.12 + wSkull*0.10;
    float pupilAmt = wRun*0.9 + wAttn*0.7 + wIdle*0.35 + wWorkV*0.85;
    float faceAmp  = wIdle*0.55 + wRun*0.90 + wDone*1.00 + wAttn*1.00 + wWorkV*0.85 + wDizzy*1.00 + wSleep*0.50
                   + wFail*1.00 + wTired*0.70 + wSkull*0.95;
    faceAmp *= nightMul;

    // blink (mostly IDLE), Gaussian dip, ~5.5s cycle -> no pow() with negative base
    float bt = fract(iTime * 0.18);
    float bz = (bt - 0.5) / 0.02;
    float blink = 1.0 - 0.92 * exp(-bz * bz);
    float eyeBlink = mix(1.0, blink, wIdle*0.9 + 0.1);

    // life: breathe (slower in SLEEP), float, RUN pulse
    float breathe = 1.0 + 0.02 * sin(iTime * 1.1 * (1.0 - 0.5 * wSleep));   // SLEEP: period x2
    vec2  flo     = vec2(sin(iTime*0.50)*0.03, sin(iTime*0.37 + 1.3)*0.02);
    float pulse   = 1.0 + wRun*0.05*sin(iTime*3.0);

    // ---------- 4. ASCII cell grid; evaluate face at CELL CENTER (blocky) ----------
    float cellH = R.y / 72.0;
    vec2  cell  = vec2(cellH * 0.5, cellH);
    vec2  cid   = floor(fragCoord / cell);
    vec2  cc    = (cid + 0.5) * cell;

    // face anchor: upper-right corner, compact size
    vec2 anchor = vec2(0.74, 0.26) * R;   // fraction of screen (x right, y from top)
    float faceScale = 0.5;
    vec2 n = (cc - anchor) / R.y;
    n.y = -n.y;                      // Metal: origin top-left -> flip so face is upright
    n -= flo;
    n /= breathe;
    n /= faceScale;

    // --- eyes ---
    float eyeW = 0.13 * pulse;
    vec2  eL = vec2(-0.22, 0.15);
    vec2  eR = vec2( 0.22, 0.15);

    // --- pupils follow the terminal cursor (Ghostty iCurrentCursor.xy = cursor pos, px) ---
    // Cursor lives in the SAME pixel space as fragCoord, so push it through the identical
    // transform chain as n (anchor -> /R.y -> flip -> flo -> breathe -> faceScale).
    vec2 curN = (iCurrentCursor.xy - anchor) / R.y;
    curN.y = -curN.y;
    curN = ((curN - flo) / breathe) / faceScale;
    vec2  rawFL   = curN - eL;
    float lenFL   = length(rawFL);
    vec2  followL = (rawFL / max(lenFL, 1e-4)) * min(lenFL, 0.40 * eyeW);   // clamp to 40% eye radius
    vec2  rawFR   = curN - eR;
    float lenFR   = length(rawFR);
    vec2  followR = (rawFR / max(lenFR, 1e-4)) * min(lenFR, 0.40 * eyeW);
    vec2  downLook = vec2(0.3 * sin(iTime * 6.0), -0.5) * 0.03;             // WORK/HELPERS: look down + type
    float wl = clamp(wWorkV, 0.0, 1.0);
    vec2  offL = mix(followL, mix(followL, downLook, 0.5), wl);             // work-like: 50/50 follow+down
    vec2  offR = mix(followR, mix(followR, downLook, 0.5), wl);
    vec2  amb  = vec2(sin(iTime*0.23), 0.4*sin(iTime*0.31)) * 0.006 * wIdle;   // idle micro-wander
    vec2  jit  = vec2(sin(iTime*1.7)*0.012, cos(iTime*1.3)*0.006) * (wRun + wAttn*0.3);
    offL += amb + jit;
    offR += amb + jit;

    vec2 pL = n - eL;
    vec2 dLe = vec2(pL.x / eyeW, pL.y / (eyeW * eyeAsp * eyeBlink));
    float discL = 1.0 - smoothstep(0.85, 1.05, length(dLe));
    float holeL = (1.0 - smoothstep(0.7, 1.0, length((pL - offL) / (eyeW * 0.45)))) * pupilAmt;
    discL *= (1.0 - holeL);
    float lxL = pL.x / eyeW;
    float arcYL = 0.05 * (0.5 - lxL * lxL);
    float arcL = (1.0 - smoothstep(0.015, 0.045, abs(pL.y - arcYL))) * (1.0 - smoothstep(0.95, 1.05, abs(lxL)));
    float eyeLv = mix(discL, arcL, arcAmt);

    vec2 pR = n - eR;
    vec2 dRe = vec2(pR.x / eyeW, pR.y / (eyeW * eyeAsp * eyeBlink));
    float discR = 1.0 - smoothstep(0.85, 1.05, length(dRe));
    float holeR = (1.0 - smoothstep(0.7, 1.0, length((pR - offR) / (eyeW * 0.45)))) * pupilAmt;
    discR *= (1.0 - holeR);
    float lxR = pR.x / eyeW;
    float arcYR = 0.05 * (0.5 - lxR * lxR);
    float arcR = (1.0 - smoothstep(0.015, 0.045, abs(pR.y - arcYR))) * (1.0 - smoothstep(0.95, 1.05, abs(lxR)));
    float eyeRv = mix(discR, arcR, arcAmt);

    // DIZZY: spinner eyes (ring with a rotating gap) replace normal eyes
    float srL = length(pL) / (eyeW * 0.9);
    float saL = atan(pL.y, pL.x);
    float gapL = step(0.5, abs(mod(saL - iTime*2.5 + 3.14159, 6.28318) - 3.14159));
    float spinL = (1.0 - smoothstep(0.85, 1.05, srL)) * smoothstep(0.55, 0.75, srL) * gapL;
    float srR = length(pR) / (eyeW * 0.9);
    float saR = atan(pR.y, pR.x);
    float gapR = step(0.5, abs(mod(saR + iTime*2.5 + 3.14159, 6.28318) - 3.14159));
    float spinR = (1.0 - smoothstep(0.85, 1.05, srR)) * smoothstep(0.55, 0.75, srR) * gapR;
    eyeLv = mix(eyeLv, spinL, wDizzy);
    eyeRv = mix(eyeRv, spinR, wDizzy);

    // SLEEP: closed eyes = short horizontal dashes
    float dashL = (1.0 - smoothstep(0.010, 0.026, abs(pL.y))) * (1.0 - smoothstep(0.85, 1.05, abs(pL.x / eyeW)));
    float dashR = (1.0 - smoothstep(0.010, 0.026, abs(pR.y))) * (1.0 - smoothstep(0.85, 1.05, abs(pR.x / eyeW)));
    eyeLv = mix(eyeLv, dashL, wSleep);
    eyeRv = mix(eyeRv, dashR, wSleep);

    // FAIL: eyes -> "><" chevrons (pained squint). Right-pointing ">" on the left eye,
    // left-pointing "<" on the right eye, read together as "><". Branchless V-stroke:
    // fold y with abs(), then band around the line ay = (x0 - ax)*k (vertex at x=x0).
    float x0F = 0.40, kF = 0.85;
    float ayL = abs(pL.y) / eyeW;
    float axL = pL.x / eyeW;
    float chevL = (1.0 - smoothstep(0.10, 0.24, abs(ayL - (x0F - axL) * kF)))
                * step(-0.55, axL) * step(axL, x0F);
    float ayR = abs(pR.y) / eyeW;
    float axR = -(pR.x / eyeW);
    float chevR = (1.0 - smoothstep(0.10, 0.24, abs(ayR - (x0F - axR) * kF)))
                * step(-0.55, axR) * step(axR, x0F);
    eyeLv = mix(eyeLv, chevL, wFail);
    eyeRv = mix(eyeRv, chevR, wFail);

    // TIRED: eyes -> heavy eyelids (only the lower half of the normal disc shows)
    float tiredL = discL * (1.0 - smoothstep(0.0, eyeW * 0.16, pL.y));
    float tiredR = discR * (1.0 - smoothstep(0.0, eyeW * 0.16, pR.y));
    eyeLv = mix(eyeLv, tiredL, wTired);
    eyeRv = mix(eyeRv, tiredR, wTired);

    // SKULL: eyes -> dark hollow eye-socket rings (lit rim only, same ring trick as "o" mouth)
    float sockRL = length(pL) / eyeW;
    float sockL  = (1.0 - smoothstep(0.85, 1.00, sockRL)) * smoothstep(0.55, 0.70, sockRL);
    float sockRR = length(pR) / eyeW;
    float sockR  = (1.0 - smoothstep(0.85, 1.00, sockRR)) * smoothstep(0.55, 0.70, sockRR);
    eyeLv = mix(eyeLv, sockL, wSkull);
    eyeRv = mix(eyeRv, sockR, wSkull);

    // --- mouth: smile stroke <-> "o" ring ---
    vec2 pM = n - vec2(0.0, -0.19);
    float lxM = pM.x / mouthW;
    float smileY = smile * (lxM * lxM - 0.33);
    float smileStroke = (1.0 - smoothstep(0.015, 0.045, abs(pM.y - smileY))) * (1.0 - smoothstep(0.95, 1.05, abs(lxM)));
    float md = length(pM);
    float oRing = (1.0 - smoothstep(0.05, 0.065, md)) * smoothstep(0.025, 0.04, md);
    float mouthV = mix(smileStroke, oRing, oAmt);

    // DIZZY: wavy mouth
    float wavyY = 0.025 * sin(lxM * 4.0 + iTime * 2.0);
    float wavy = (1.0 - smoothstep(0.015, 0.045, abs(pM.y - wavyY))) * (1.0 - smoothstep(0.95, 1.05, abs(lxM)));
    mouthV = mix(mouthV, wavy, wDizzy);

    // SLEEP: tiny neutral mouth
    float sleepMouth = (1.0 - smoothstep(0.008, 0.022, abs(pM.y))) * (1.0 - smoothstep(0.4, 0.6, abs(lxM)));
    mouthV = mix(mouthV, sleepMouth, wSleep);

    // FAIL: mouth -> straight flat line (pained/firm)
    float failMouth = (1.0 - smoothstep(0.012, 0.030, abs(pM.y))) * (1.0 - smoothstep(0.55, 0.70, abs(lxM)));
    mouthV = mix(mouthV, failMouth, wFail);

    // SKULL: mouth -> row of short vertical teeth strokes (comb pattern via fract)
    float toothSpace = 0.075;
    float toothX = abs(fract(pM.x / toothSpace + 0.5) - 0.5) * toothSpace;
    float teeth = (1.0 - smoothstep(0.010, 0.020, toothX))
                * (1.0 - smoothstep(0.055, 0.075, abs(pM.y)))
                * step(abs(pM.x), 0.145);
    mouthV = mix(mouthV, teeth, wSkull);

    // --- "?" beside face (RUN only), gently bobbing ---
    vec2 qp = (n - vec2(0.47, 0.12 + 0.03*sin(iTime*2.0))) / 0.16;
    float qr = length(qp - vec2(0.0, 0.5));
    float qband = (1.0 - smoothstep(0.46, 0.54, qr)) * smoothstep(0.34, 0.42, qr);
    float qa = atan(qp.y - 0.5, qp.x);
    float lower = step(-2.95, qa) * step(qa, -1.5);      // open the lower-left -> "?" hook
    float qv = qband * (1.0 - lower);
    qv = max(qv, 1.0 - smoothstep(0.09, 0.15, length(qp - vec2(0.0, -0.5)))); // dot
    qv *= wRun;

    // --- "!" beside face (ATTN only), pulsing ---
    vec2 xp = (n - vec2(0.47, 0.12)) / 0.16;
    float xbar = (1.0 - smoothstep(0.10, 0.16, abs(xp.x))) * (1.0 - smoothstep(0.55, 0.65, abs(xp.y - 0.35)));
    float xdot = 1.0 - smoothstep(0.10, 0.16, length(xp - vec2(0.0, -0.55)));
    float xv = max(xbar, xdot) * wAttn * (0.75 + 0.25*sin(iTime*5.0));

    // --- "..." beside face (WORK + HELPERS), dots pulsing in sequence ---
    float dots = (1.0 - smoothstep(0.030, 0.050, length(n - vec2(0.40, -0.02)))) * (0.35 + 0.65*max(0.0, sin(iTime*3.0)));
    dots = max(dots, (1.0 - smoothstep(0.030, 0.050, length(n - vec2(0.50, -0.02)))) * (0.35 + 0.65*max(0.0, sin(iTime*3.0 - 1.1))));
    dots = max(dots, (1.0 - smoothstep(0.030, 0.050, length(n - vec2(0.60, -0.02)))) * (0.35 + 0.65*max(0.0, sin(iTime*3.0 - 2.2))));
    dots *= wWorkV;

    // --- SLEEP: three "Z" drifting up-right, growing, soft sequential fade ---
    float zt = iTime * 0.6;
    float zv = zGlyph((n - vec2(0.46, 0.30)) / 0.10) * (0.5 + 0.5*sin(zt));
    zv = max(zv, zGlyph((n - vec2(0.66, 0.52)) / 0.15) * (0.5 + 0.5*sin(zt - 2.0944)));
    zv = max(zv, zGlyph((n - vec2(0.90, 0.80)) / 0.22) * (0.5 + 0.5*sin(zt - 4.1888)));
    zv *= wSleep;

    // --- HELPERS: two pairs of small satellite eyes, left-top & left-bottom, antiphase sway ---
    float satW  = eyeW * 0.25;
    float satG  = satW * 1.6;                       // spacing within a pair
    float sway  = 0.03 * sin(iTime * 2.2);
    vec2  upC = vec2(-0.56, 0.34 + sway);           // upper-left pair
    vec2  loC = vec2(-0.56, -0.24 - sway);          // lower-left pair (antiphase)
    float sat = 1.0 - smoothstep(0.85, 1.05, length((n - (upC + vec2(-satG, 0.0))) / satW));
    sat = max(sat, 1.0 - smoothstep(0.85, 1.05, length((n - (upC + vec2( satG, 0.0))) / satW)));
    sat = max(sat, 1.0 - smoothstep(0.85, 1.05, length((n - (loC + vec2(-satG, 0.0))) / satW)));
    sat = max(sat, 1.0 - smoothstep(0.85, 1.05, length((n - (loC + vec2( satG, 0.0))) / satW)));
    sat *= wHelp;

    // SKULL: small nose triangle between the eyes (downward chevron, same V-stroke trick as FAIL eyes)
    vec2  pNose = n - vec2(0.0, 0.00);
    float ayN = abs(pNose.x) / 0.09;
    float axN = -(pNose.y / 0.09);
    float nose = (1.0 - smoothstep(0.12, 0.28, abs(ayN - (0.55 - axN) * 0.9)))
               * step(-0.35, axN) * step(axN, 0.55);
    nose *= wSkull;

    // TIRED: 3-5 dim dots in a row under the face
    float dotSpace = 0.09;
    float tdx = abs(fract(n.x / dotSpace + 0.5) - 0.5) * dotSpace;
    float tdy = abs(n.y - (-0.40));
    float tiredDots = (1.0 - smoothstep(0.018, 0.030, tdx))
                    * (1.0 - smoothstep(0.018, 0.030, tdy))
                    * step(abs(n.x), 0.16)
                    * 0.45;                                         // dim ("тусклые")
    tiredDots *= wTired;

    float field = max(max(eyeLv, eyeRv), max(mouthV, max(qv, max(xv, max(dots, max(zv, max(sat, max(nose, tiredDots))))))));
    field = clamp(field, 0.0, 1.0);

    // ---------- 4b. SLEEP aquarium: 4 ASCII fish (stateless Lissajous wander) ----------
    float aq   = wSleep;                              // aquarium lives ONLY in SLEEP (crossfades with the weight)
    vec2  fp    = vec2(cc.x, R.y - cc.y) / R.y;                         // screen space, Y-up, isotropic
    vec2  curFp = vec2(iCurrentCursor.x, R.y - iCurrentCursor.y) / R.y; // cursor in the same space
    float tN = iTime;          // near fish
    float tF = iTime * 0.6;    // far fish (slower)
    float aspect = R.x / R.y;
    // fish roam the WHOLE window (centers spread across the width, x-amps scale with it);
    // they cruise the mid-water: above the weeds/crab, below the face zone.
    float cov1 = fishCov(fp, vec2(aspect*0.22, 0.42), vec4(aspect*0.075,aspect*0.028,0.055,0.022), vec4(0.31,0.73,0.41,0.97), vec4(0.0,1.7,2.3,0.9), tF, 0.045, 0.018, 0.0, curFp) * 0.5; // far
    float cov2 = fishCov(fp, vec2(aspect*0.60, 0.50), vec4(aspect*0.070,aspect*0.030,0.050,0.020), vec4(0.27,0.61,0.47,0.89), vec4(1.1,2.4,0.5,3.0), tF, 0.045, 0.018, 1.5, curFp) * 0.5; // far
    float cov3 = fishCov(fp, vec2(aspect*0.38, 0.38), vec4(aspect*0.085,aspect*0.030,0.070,0.028), vec4(0.23,0.67,0.37,0.83), vec4(0.6,2.9,1.4,2.1), tN, 0.070, 0.028, 0.7, curFp);       // near
    float cov4 = fishCov(fp, vec2(aspect*0.72, 0.30), vec4(aspect*0.080,aspect*0.032,0.065,0.025), vec4(0.29,0.59,0.43,0.79), vec4(2.2,0.4,3.1,1.2), tN, 0.062, 0.025, 2.6, curFp);       // near

    // fish in distinct hues: blue, teal, warm sand, violet
    vec3 fc1 = vec3(0.42, 0.55, 0.85);
    vec3 fc2 = vec3(0.40, 0.72, 0.55);
    vec3 fc3 = vec3(0.85, 0.62, 0.38);
    vec3 fc4 = vec3(0.68, 0.50, 0.85);

    // seaweed clusters from the "substrate": ribbons + leafy bushes, varied heights/widths
    float weedA = weedCov(fp, aspect*0.06,  0.22, 0.0, iTime, 0.009, 0.0);
    weedA = max(weedA, weedCov(fp, aspect*0.085, 0.11, 1.9, iTime, 0.014, 0.0));
    weedA = max(weedA, weedCov(fp, aspect*0.475, 0.13, 2.8, iTime, 0.007, 0.0));
    float weedB = weedCov(fp, aspect*0.45,  0.19, 0.7, iTime, 0.013, 1.0);
    weedB = max(weedB, weedCov(fp, aspect*0.62, 0.09, 4.1, iTime, 0.016, 1.0));
    weedB = max(weedB, weedCov(fp, aspect*0.88, 0.15, 1.2, iTime, 0.011, 1.0));
    vec3 weedAC = vec3(0.30, 0.52, 0.38);
    vec3 weedBC = vec3(0.44, 0.68, 0.44);

    // crab patrols the substrate; its range ends BEFORE the turtle by construction
    float turtleX = aspect - 0.11;
    float crab = crabCov(fp, iTime, aspect * 0.10, turtleX - 0.16);
    float turt = turtleCov(fp, iTime, turtleX);
    vec3 crabC = vec3(0.88, 0.45, 0.30);
    vec3 turtC = vec3(0.50, 0.62, 0.45);

    float fishField = max(max(max(cov1, cov2), max(cov3, cov4)),
                      max(max(weedA * 0.8, weedB * 0.85), max(crab, turt)));
    float fwsum = cov1 + cov2 + cov3 + cov4 + weedA + weedB + crab + turt + 1e-4;
    vec3  fishCol = (fc1*cov1 + fc2*cov2 + fc3*cov3 + fc4*cov4
                   + weedAC*weedA + weedBC*weedB + crabC*crab + turtC*turt) / fwsum;
    fishCol = mix(fishCol, cSleep, 0.25);                               // night tint, hues stay visible

    // bubbles: rare columns, dot cells rising (wrap by y), fading in the top third
    float colH   = hash21(vec2(cid.x, 3.0));
    float by     = fract(iTime * 0.10 + colH * 7.0);
    float cellYup = (R.y - cc.y) / R.y;
    float cellHn  = cell.y / R.y;
    float bub = step(0.88, colH) * (1.0 - smoothstep(0.5, 1.4, abs(cellYup - by) / cellHn));
    bub *= (1.0 - smoothstep(0.62, 0.92, by));
    fishField = max(fishField, bub * 0.55);

    // ---------- 5. mini-glyph inside the actual pixel's cell ----------
    vec2 lp = (fragCoord - cid * cell) / cell;
    vec2 g  = lp - 0.5;
    float ob = sdRoundBox(g, vec2(0.30, 0.36), 0.12);
    float ib = sdRoundBox(g, vec2(0.16, 0.20), 0.07);
    float aa = 0.03;
    float gRing  = 1.0 - smoothstep(0.0, aa, max(ob, -ib)); // "0"
    float gBlock = 1.0 - smoothstep(0.0, aa, ob);           // block
    float gDot   = 1.0 - smoothstep(0.14, 0.18, length(g)); // dot
    float h = hash21(cid);
    float gv = mix(gRing, gBlock, step(0.55, h));
    gv = mix(gv, gDot, step(0.82, h));

    // core cells + sparse edge "dust" halo
    float core = step(0.34, field);
    float dust = step(0.10, field) * (1.0 - step(0.34, field)) * step(0.86, h);
    gv = mix(gv, gDot, dust);
    float lit = gv * (core * field + dust * 0.55);

    // DONE: sparse fireflies twinkling across the background
    float sparkle = step(0.965, h) * wDone * max(0.0, sin(iTime * 2.5 + h * 80.0));
    lit += gDot * sparkle * 0.5;

    // readability: a cell that contains terminal text goes dark
    vec3 t1 = texture(iChannel0, (cc + vec2(-0.35, -0.25) * cell) / R).rgb;
    vec3 t2 = texture(iChannel0, (cc + vec2( 0.35,  0.25) * cell) / R).rgb;
    vec3 t3 = texture(iChannel0, cc / R).rgb;
    float textIn = max(max(smoothstep(0.06, 0.15, distance(t1, bg)),
                           smoothstep(0.06, 0.15, distance(t2, bg))),
                           smoothstep(0.06, 0.15, distance(t3, bg)));
    lit *= 1.0 - 0.85 * textIn;

    // aquarium ink: same cell glyph + same text-dim as the face, separate colour layer
    float fishCore = step(0.30, fishField);
    float fishLit  = gv * fishField * fishCore;
    fishLit *= 1.0 - 0.85 * textIn;

    // ---------- 6. compose: force BASE_BG on signal, protect text, draw face + fish ----------
    vec3 term = texture(iChannel0, uv).rgb;
    float bgd = distance(term, bg);                 // distance to SAMPLED corner color
    float bgMask = 1.0 - smoothstep(0.05, 0.16, bgd);

    vec3 base = mix(term, BASE_BG, bgMask * signalActive); // repaint bg back to #282c34
    float bright = 0.34;
    vec3 add = faceCol * lit * bgMask * faceAmp * bright;
    add += fishCol * fishLit * bgMask * faceAmp * bright * aq;   // fish: idle/sleep only, dimmed by faceAmp*nightMul

    fragColor = vec4(base + add, 1.0);
}

# AES-128/256 block cipher (FIPS-197) + ECB/CBC/CTR. Verified vs FIPS-197 App C.1/C.2.
# 状态布局 st[col*4+row]；w[round*16+col*4+row]。

var AES_SBOX: [256] i64 = 0;
var AES_ISBOX: [256] i64 = 0;
var AES_INITED: i64 = 0;

fn aes_init() {
    if AES_INITED == 1 {
        return 0;
    }
    let k: i64 = 0;
    AES_SBOX[k+0] = 99; AES_SBOX[k+1] = 124; AES_SBOX[k+2] = 119; AES_SBOX[k+3] = 123; AES_SBOX[k+4] = 242; AES_SBOX[k+5] = 107; AES_SBOX[k+6] = 111; AES_SBOX[k+7] = 197;
    k = k + 8;
    AES_SBOX[k+0] = 48; AES_SBOX[k+1] = 1; AES_SBOX[k+2] = 103; AES_SBOX[k+3] = 43; AES_SBOX[k+4] = 254; AES_SBOX[k+5] = 215; AES_SBOX[k+6] = 171; AES_SBOX[k+7] = 118;
    k = k + 8;
    AES_SBOX[k+0] = 202; AES_SBOX[k+1] = 130; AES_SBOX[k+2] = 201; AES_SBOX[k+3] = 125; AES_SBOX[k+4] = 250; AES_SBOX[k+5] = 89; AES_SBOX[k+6] = 71; AES_SBOX[k+7] = 240;
    k = k + 8;
    AES_SBOX[k+0] = 173; AES_SBOX[k+1] = 212; AES_SBOX[k+2] = 162; AES_SBOX[k+3] = 175; AES_SBOX[k+4] = 156; AES_SBOX[k+5] = 164; AES_SBOX[k+6] = 114; AES_SBOX[k+7] = 192;
    k = k + 8;
    AES_SBOX[k+0] = 183; AES_SBOX[k+1] = 253; AES_SBOX[k+2] = 147; AES_SBOX[k+3] = 38; AES_SBOX[k+4] = 54; AES_SBOX[k+5] = 63; AES_SBOX[k+6] = 247; AES_SBOX[k+7] = 204;
    k = k + 8;
    AES_SBOX[k+0] = 52; AES_SBOX[k+1] = 165; AES_SBOX[k+2] = 229; AES_SBOX[k+3] = 241; AES_SBOX[k+4] = 113; AES_SBOX[k+5] = 216; AES_SBOX[k+6] = 49; AES_SBOX[k+7] = 21;
    k = k + 8;
    AES_SBOX[k+0] = 4; AES_SBOX[k+1] = 199; AES_SBOX[k+2] = 35; AES_SBOX[k+3] = 195; AES_SBOX[k+4] = 24; AES_SBOX[k+5] = 150; AES_SBOX[k+6] = 5; AES_SBOX[k+7] = 154;
    k = k + 8;
    AES_SBOX[k+0] = 7; AES_SBOX[k+1] = 18; AES_SBOX[k+2] = 128; AES_SBOX[k+3] = 226; AES_SBOX[k+4] = 235; AES_SBOX[k+5] = 39; AES_SBOX[k+6] = 178; AES_SBOX[k+7] = 117;
    k = k + 8;
    AES_SBOX[k+0] = 9; AES_SBOX[k+1] = 131; AES_SBOX[k+2] = 44; AES_SBOX[k+3] = 26; AES_SBOX[k+4] = 27; AES_SBOX[k+5] = 110; AES_SBOX[k+6] = 90; AES_SBOX[k+7] = 160;
    k = k + 8;
    AES_SBOX[k+0] = 82; AES_SBOX[k+1] = 59; AES_SBOX[k+2] = 214; AES_SBOX[k+3] = 179; AES_SBOX[k+4] = 41; AES_SBOX[k+5] = 227; AES_SBOX[k+6] = 47; AES_SBOX[k+7] = 132;
    k = k + 8;
    AES_SBOX[k+0] = 83; AES_SBOX[k+1] = 209; AES_SBOX[k+2] = 0; AES_SBOX[k+3] = 237; AES_SBOX[k+4] = 32; AES_SBOX[k+5] = 252; AES_SBOX[k+6] = 177; AES_SBOX[k+7] = 91;
    k = k + 8;
    AES_SBOX[k+0] = 106; AES_SBOX[k+1] = 203; AES_SBOX[k+2] = 190; AES_SBOX[k+3] = 57; AES_SBOX[k+4] = 74; AES_SBOX[k+5] = 76; AES_SBOX[k+6] = 88; AES_SBOX[k+7] = 207;
    k = k + 8;
    AES_SBOX[k+0] = 208; AES_SBOX[k+1] = 239; AES_SBOX[k+2] = 170; AES_SBOX[k+3] = 251; AES_SBOX[k+4] = 67; AES_SBOX[k+5] = 77; AES_SBOX[k+6] = 51; AES_SBOX[k+7] = 133;
    k = k + 8;
    AES_SBOX[k+0] = 69; AES_SBOX[k+1] = 249; AES_SBOX[k+2] = 2; AES_SBOX[k+3] = 127; AES_SBOX[k+4] = 80; AES_SBOX[k+5] = 60; AES_SBOX[k+6] = 159; AES_SBOX[k+7] = 168;
    k = k + 8;
    AES_SBOX[k+0] = 81; AES_SBOX[k+1] = 163; AES_SBOX[k+2] = 64; AES_SBOX[k+3] = 143; AES_SBOX[k+4] = 146; AES_SBOX[k+5] = 157; AES_SBOX[k+6] = 56; AES_SBOX[k+7] = 245;
    k = k + 8;
    AES_SBOX[k+0] = 188; AES_SBOX[k+1] = 182; AES_SBOX[k+2] = 218; AES_SBOX[k+3] = 33; AES_SBOX[k+4] = 16; AES_SBOX[k+5] = 255; AES_SBOX[k+6] = 243; AES_SBOX[k+7] = 210;
    k = k + 8;
    AES_SBOX[k+0] = 205; AES_SBOX[k+1] = 12; AES_SBOX[k+2] = 19; AES_SBOX[k+3] = 236; AES_SBOX[k+4] = 95; AES_SBOX[k+5] = 151; AES_SBOX[k+6] = 68; AES_SBOX[k+7] = 23;
    k = k + 8;
    AES_SBOX[k+0] = 196; AES_SBOX[k+1] = 167; AES_SBOX[k+2] = 126; AES_SBOX[k+3] = 61; AES_SBOX[k+4] = 100; AES_SBOX[k+5] = 93; AES_SBOX[k+6] = 25; AES_SBOX[k+7] = 115;
    k = k + 8;
    AES_SBOX[k+0] = 96; AES_SBOX[k+1] = 129; AES_SBOX[k+2] = 79; AES_SBOX[k+3] = 220; AES_SBOX[k+4] = 34; AES_SBOX[k+5] = 42; AES_SBOX[k+6] = 144; AES_SBOX[k+7] = 136;
    k = k + 8;
    AES_SBOX[k+0] = 70; AES_SBOX[k+1] = 238; AES_SBOX[k+2] = 184; AES_SBOX[k+3] = 20; AES_SBOX[k+4] = 222; AES_SBOX[k+5] = 94; AES_SBOX[k+6] = 11; AES_SBOX[k+7] = 219;
    k = k + 8;
    AES_SBOX[k+0] = 224; AES_SBOX[k+1] = 50; AES_SBOX[k+2] = 58; AES_SBOX[k+3] = 10; AES_SBOX[k+4] = 73; AES_SBOX[k+5] = 6; AES_SBOX[k+6] = 36; AES_SBOX[k+7] = 92;
    k = k + 8;
    AES_SBOX[k+0] = 194; AES_SBOX[k+1] = 211; AES_SBOX[k+2] = 172; AES_SBOX[k+3] = 98; AES_SBOX[k+4] = 145; AES_SBOX[k+5] = 149; AES_SBOX[k+6] = 228; AES_SBOX[k+7] = 121;
    k = k + 8;
    AES_SBOX[k+0] = 231; AES_SBOX[k+1] = 200; AES_SBOX[k+2] = 55; AES_SBOX[k+3] = 109; AES_SBOX[k+4] = 141; AES_SBOX[k+5] = 213; AES_SBOX[k+6] = 78; AES_SBOX[k+7] = 169;
    k = k + 8;
    AES_SBOX[k+0] = 108; AES_SBOX[k+1] = 86; AES_SBOX[k+2] = 244; AES_SBOX[k+3] = 234; AES_SBOX[k+4] = 101; AES_SBOX[k+5] = 122; AES_SBOX[k+6] = 174; AES_SBOX[k+7] = 8;
    k = k + 8;
    AES_SBOX[k+0] = 186; AES_SBOX[k+1] = 120; AES_SBOX[k+2] = 37; AES_SBOX[k+3] = 46; AES_SBOX[k+4] = 28; AES_SBOX[k+5] = 166; AES_SBOX[k+6] = 180; AES_SBOX[k+7] = 198;
    k = k + 8;
    AES_SBOX[k+0] = 232; AES_SBOX[k+1] = 221; AES_SBOX[k+2] = 116; AES_SBOX[k+3] = 31; AES_SBOX[k+4] = 75; AES_SBOX[k+5] = 189; AES_SBOX[k+6] = 139; AES_SBOX[k+7] = 138;
    k = k + 8;
    AES_SBOX[k+0] = 112; AES_SBOX[k+1] = 62; AES_SBOX[k+2] = 181; AES_SBOX[k+3] = 102; AES_SBOX[k+4] = 72; AES_SBOX[k+5] = 3; AES_SBOX[k+6] = 246; AES_SBOX[k+7] = 14;
    k = k + 8;
    AES_SBOX[k+0] = 97; AES_SBOX[k+1] = 53; AES_SBOX[k+2] = 87; AES_SBOX[k+3] = 185; AES_SBOX[k+4] = 134; AES_SBOX[k+5] = 193; AES_SBOX[k+6] = 29; AES_SBOX[k+7] = 158;
    k = k + 8;
    AES_SBOX[k+0] = 225; AES_SBOX[k+1] = 248; AES_SBOX[k+2] = 152; AES_SBOX[k+3] = 17; AES_SBOX[k+4] = 105; AES_SBOX[k+5] = 217; AES_SBOX[k+6] = 142; AES_SBOX[k+7] = 148;
    k = k + 8;
    AES_SBOX[k+0] = 155; AES_SBOX[k+1] = 30; AES_SBOX[k+2] = 135; AES_SBOX[k+3] = 233; AES_SBOX[k+4] = 206; AES_SBOX[k+5] = 85; AES_SBOX[k+6] = 40; AES_SBOX[k+7] = 223;
    k = k + 8;
    AES_SBOX[k+0] = 140; AES_SBOX[k+1] = 161; AES_SBOX[k+2] = 137; AES_SBOX[k+3] = 13; AES_SBOX[k+4] = 191; AES_SBOX[k+5] = 230; AES_SBOX[k+6] = 66; AES_SBOX[k+7] = 104;
    k = k + 8;
    AES_SBOX[k+0] = 65; AES_SBOX[k+1] = 153; AES_SBOX[k+2] = 45; AES_SBOX[k+3] = 15; AES_SBOX[k+4] = 176; AES_SBOX[k+5] = 84; AES_SBOX[k+6] = 187; AES_SBOX[k+7] = 22;
    k = k + 8;
    k = 0;
    AES_ISBOX[k+0] = 82; AES_ISBOX[k+1] = 9; AES_ISBOX[k+2] = 106; AES_ISBOX[k+3] = 213; AES_ISBOX[k+4] = 48; AES_ISBOX[k+5] = 54; AES_ISBOX[k+6] = 165; AES_ISBOX[k+7] = 56;
    k = k + 8;
    AES_ISBOX[k+0] = 191; AES_ISBOX[k+1] = 64; AES_ISBOX[k+2] = 163; AES_ISBOX[k+3] = 158; AES_ISBOX[k+4] = 129; AES_ISBOX[k+5] = 243; AES_ISBOX[k+6] = 215; AES_ISBOX[k+7] = 251;
    k = k + 8;
    AES_ISBOX[k+0] = 124; AES_ISBOX[k+1] = 227; AES_ISBOX[k+2] = 57; AES_ISBOX[k+3] = 130; AES_ISBOX[k+4] = 155; AES_ISBOX[k+5] = 47; AES_ISBOX[k+6] = 255; AES_ISBOX[k+7] = 135;
    k = k + 8;
    AES_ISBOX[k+0] = 52; AES_ISBOX[k+1] = 142; AES_ISBOX[k+2] = 67; AES_ISBOX[k+3] = 68; AES_ISBOX[k+4] = 196; AES_ISBOX[k+5] = 222; AES_ISBOX[k+6] = 233; AES_ISBOX[k+7] = 203;
    k = k + 8;
    AES_ISBOX[k+0] = 84; AES_ISBOX[k+1] = 123; AES_ISBOX[k+2] = 148; AES_ISBOX[k+3] = 50; AES_ISBOX[k+4] = 166; AES_ISBOX[k+5] = 194; AES_ISBOX[k+6] = 35; AES_ISBOX[k+7] = 61;
    k = k + 8;
    AES_ISBOX[k+0] = 238; AES_ISBOX[k+1] = 76; AES_ISBOX[k+2] = 149; AES_ISBOX[k+3] = 11; AES_ISBOX[k+4] = 66; AES_ISBOX[k+5] = 250; AES_ISBOX[k+6] = 195; AES_ISBOX[k+7] = 78;
    k = k + 8;
    AES_ISBOX[k+0] = 8; AES_ISBOX[k+1] = 46; AES_ISBOX[k+2] = 161; AES_ISBOX[k+3] = 102; AES_ISBOX[k+4] = 40; AES_ISBOX[k+5] = 217; AES_ISBOX[k+6] = 36; AES_ISBOX[k+7] = 178;
    k = k + 8;
    AES_ISBOX[k+0] = 118; AES_ISBOX[k+1] = 91; AES_ISBOX[k+2] = 162; AES_ISBOX[k+3] = 73; AES_ISBOX[k+4] = 109; AES_ISBOX[k+5] = 139; AES_ISBOX[k+6] = 209; AES_ISBOX[k+7] = 37;
    k = k + 8;
    AES_ISBOX[k+0] = 114; AES_ISBOX[k+1] = 248; AES_ISBOX[k+2] = 246; AES_ISBOX[k+3] = 100; AES_ISBOX[k+4] = 134; AES_ISBOX[k+5] = 104; AES_ISBOX[k+6] = 152; AES_ISBOX[k+7] = 22;
    k = k + 8;
    AES_ISBOX[k+0] = 212; AES_ISBOX[k+1] = 164; AES_ISBOX[k+2] = 92; AES_ISBOX[k+3] = 204; AES_ISBOX[k+4] = 93; AES_ISBOX[k+5] = 101; AES_ISBOX[k+6] = 182; AES_ISBOX[k+7] = 146;
    k = k + 8;
    AES_ISBOX[k+0] = 108; AES_ISBOX[k+1] = 112; AES_ISBOX[k+2] = 72; AES_ISBOX[k+3] = 80; AES_ISBOX[k+4] = 253; AES_ISBOX[k+5] = 237; AES_ISBOX[k+6] = 185; AES_ISBOX[k+7] = 218;
    k = k + 8;
    AES_ISBOX[k+0] = 94; AES_ISBOX[k+1] = 21; AES_ISBOX[k+2] = 70; AES_ISBOX[k+3] = 87; AES_ISBOX[k+4] = 167; AES_ISBOX[k+5] = 141; AES_ISBOX[k+6] = 157; AES_ISBOX[k+7] = 132;
    k = k + 8;
    AES_ISBOX[k+0] = 144; AES_ISBOX[k+1] = 216; AES_ISBOX[k+2] = 171; AES_ISBOX[k+3] = 0; AES_ISBOX[k+4] = 140; AES_ISBOX[k+5] = 188; AES_ISBOX[k+6] = 211; AES_ISBOX[k+7] = 10;
    k = k + 8;
    AES_ISBOX[k+0] = 247; AES_ISBOX[k+1] = 228; AES_ISBOX[k+2] = 88; AES_ISBOX[k+3] = 5; AES_ISBOX[k+4] = 184; AES_ISBOX[k+5] = 179; AES_ISBOX[k+6] = 69; AES_ISBOX[k+7] = 6;
    k = k + 8;
    AES_ISBOX[k+0] = 208; AES_ISBOX[k+1] = 44; AES_ISBOX[k+2] = 30; AES_ISBOX[k+3] = 143; AES_ISBOX[k+4] = 202; AES_ISBOX[k+5] = 63; AES_ISBOX[k+6] = 15; AES_ISBOX[k+7] = 2;
    k = k + 8;
    AES_ISBOX[k+0] = 193; AES_ISBOX[k+1] = 175; AES_ISBOX[k+2] = 189; AES_ISBOX[k+3] = 3; AES_ISBOX[k+4] = 1; AES_ISBOX[k+5] = 19; AES_ISBOX[k+6] = 138; AES_ISBOX[k+7] = 107;
    k = k + 8;
    AES_ISBOX[k+0] = 58; AES_ISBOX[k+1] = 145; AES_ISBOX[k+2] = 17; AES_ISBOX[k+3] = 65; AES_ISBOX[k+4] = 79; AES_ISBOX[k+5] = 103; AES_ISBOX[k+6] = 220; AES_ISBOX[k+7] = 234;
    k = k + 8;
    AES_ISBOX[k+0] = 151; AES_ISBOX[k+1] = 242; AES_ISBOX[k+2] = 207; AES_ISBOX[k+3] = 206; AES_ISBOX[k+4] = 240; AES_ISBOX[k+5] = 180; AES_ISBOX[k+6] = 230; AES_ISBOX[k+7] = 115;
    k = k + 8;
    AES_ISBOX[k+0] = 150; AES_ISBOX[k+1] = 172; AES_ISBOX[k+2] = 116; AES_ISBOX[k+3] = 34; AES_ISBOX[k+4] = 231; AES_ISBOX[k+5] = 173; AES_ISBOX[k+6] = 53; AES_ISBOX[k+7] = 133;
    k = k + 8;
    AES_ISBOX[k+0] = 226; AES_ISBOX[k+1] = 249; AES_ISBOX[k+2] = 55; AES_ISBOX[k+3] = 232; AES_ISBOX[k+4] = 28; AES_ISBOX[k+5] = 117; AES_ISBOX[k+6] = 223; AES_ISBOX[k+7] = 110;
    k = k + 8;
    AES_ISBOX[k+0] = 71; AES_ISBOX[k+1] = 241; AES_ISBOX[k+2] = 26; AES_ISBOX[k+3] = 113; AES_ISBOX[k+4] = 29; AES_ISBOX[k+5] = 41; AES_ISBOX[k+6] = 197; AES_ISBOX[k+7] = 137;
    k = k + 8;
    AES_ISBOX[k+0] = 111; AES_ISBOX[k+1] = 183; AES_ISBOX[k+2] = 98; AES_ISBOX[k+3] = 14; AES_ISBOX[k+4] = 170; AES_ISBOX[k+5] = 24; AES_ISBOX[k+6] = 190; AES_ISBOX[k+7] = 27;
    k = k + 8;
    AES_ISBOX[k+0] = 252; AES_ISBOX[k+1] = 86; AES_ISBOX[k+2] = 62; AES_ISBOX[k+3] = 75; AES_ISBOX[k+4] = 198; AES_ISBOX[k+5] = 210; AES_ISBOX[k+6] = 121; AES_ISBOX[k+7] = 32;
    k = k + 8;
    AES_ISBOX[k+0] = 154; AES_ISBOX[k+1] = 219; AES_ISBOX[k+2] = 192; AES_ISBOX[k+3] = 254; AES_ISBOX[k+4] = 120; AES_ISBOX[k+5] = 205; AES_ISBOX[k+6] = 90; AES_ISBOX[k+7] = 244;
    k = k + 8;
    AES_ISBOX[k+0] = 31; AES_ISBOX[k+1] = 221; AES_ISBOX[k+2] = 168; AES_ISBOX[k+3] = 51; AES_ISBOX[k+4] = 136; AES_ISBOX[k+5] = 7; AES_ISBOX[k+6] = 199; AES_ISBOX[k+7] = 49;
    k = k + 8;
    AES_ISBOX[k+0] = 177; AES_ISBOX[k+1] = 18; AES_ISBOX[k+2] = 16; AES_ISBOX[k+3] = 89; AES_ISBOX[k+4] = 39; AES_ISBOX[k+5] = 128; AES_ISBOX[k+6] = 236; AES_ISBOX[k+7] = 95;
    k = k + 8;
    AES_ISBOX[k+0] = 96; AES_ISBOX[k+1] = 81; AES_ISBOX[k+2] = 127; AES_ISBOX[k+3] = 169; AES_ISBOX[k+4] = 25; AES_ISBOX[k+5] = 181; AES_ISBOX[k+6] = 74; AES_ISBOX[k+7] = 13;
    k = k + 8;
    AES_ISBOX[k+0] = 45; AES_ISBOX[k+1] = 229; AES_ISBOX[k+2] = 122; AES_ISBOX[k+3] = 159; AES_ISBOX[k+4] = 147; AES_ISBOX[k+5] = 201; AES_ISBOX[k+6] = 156; AES_ISBOX[k+7] = 239;
    k = k + 8;
    AES_ISBOX[k+0] = 160; AES_ISBOX[k+1] = 224; AES_ISBOX[k+2] = 59; AES_ISBOX[k+3] = 77; AES_ISBOX[k+4] = 174; AES_ISBOX[k+5] = 42; AES_ISBOX[k+6] = 245; AES_ISBOX[k+7] = 176;
    k = k + 8;
    AES_ISBOX[k+0] = 200; AES_ISBOX[k+1] = 235; AES_ISBOX[k+2] = 187; AES_ISBOX[k+3] = 60; AES_ISBOX[k+4] = 131; AES_ISBOX[k+5] = 83; AES_ISBOX[k+6] = 153; AES_ISBOX[k+7] = 97;
    k = k + 8;
    AES_ISBOX[k+0] = 23; AES_ISBOX[k+1] = 43; AES_ISBOX[k+2] = 4; AES_ISBOX[k+3] = 126; AES_ISBOX[k+4] = 186; AES_ISBOX[k+5] = 119; AES_ISBOX[k+6] = 214; AES_ISBOX[k+7] = 38;
    k = k + 8;
    AES_ISBOX[k+0] = 225; AES_ISBOX[k+1] = 105; AES_ISBOX[k+2] = 20; AES_ISBOX[k+3] = 99; AES_ISBOX[k+4] = 85; AES_ISBOX[k+5] = 33; AES_ISBOX[k+6] = 12; AES_ISBOX[k+7] = 125;
    k = k + 8;
    AES_INITED = 1;
}

fn aes_xtime(x: i64) -> i64 {
    let h: i64 = x & 128;
    let r: i64 = (x << 1) & 255;
    if h != 0 {
        r = r ^ 27;
    }
    return r;
}

fn aes_mul(a: i64, b: i64) -> i64 {
    let p: i64 = 0;
    let aa: i64 = a;
    let bb: i64 = b;
    let i: i64 = 0;
    while i < 8 {
        if (bb & 1) == 1 {
            p = p ^ aa;
        }
        aa = aes_xtime(aa);
        bb = bb >> 1;
        i = i + 1;
    }
    return p & 255;
}

fn aes_key_expand(nk: i64, key: ptr, w: ptr) {
    let i: i64 = 0;
    while i < nk {
        w[i * 4] = load8(key + i * 4);
        w[i * 4 + 1] = load8(key + i * 4 + 1);
        w[i * 4 + 2] = load8(key + i * 4 + 2);
        w[i * 4 + 3] = load8(key + i * 4 + 3);
        i = i + 1;
    }
    let rcon: i64 = 1;
    i = nk;
    let total: i64 = 4 * (nk + 7);
    while i < total {
        let b0: i64 = w[(i-1) * 4];
        let b1: i64 = w[(i-1) * 4 + 1];
        let b2: i64 = w[(i-1) * 4 + 2];
        let b3: i64 = w[(i-1) * 4 + 3];
        let t0: i64 = b0;
        let t1: i64 = b1;
        let t2: i64 = b2;
        let t3: i64 = b3;
        if (i % nk) == 0 {
            t0 = AES_SBOX[b1] ^ rcon;
            t1 = AES_SBOX[b2];
            t2 = AES_SBOX[b3];
            t3 = AES_SBOX[b0];
            rcon = aes_xtime(rcon);
        }
        let sw: i64 = 0;
        if nk > 6 { if (i % nk) == 4 { sw = 1; } }
        if sw == 1 {
            t0 = AES_SBOX[b0];
            t1 = AES_SBOX[b1];
            t2 = AES_SBOX[b2];
            t3 = AES_SBOX[b3];
        }
        w[i * 4] = w[(i-nk) * 4] ^ t0;
        w[i * 4 + 1] = w[(i-nk) * 4 + 1] ^ t1;
        w[i * 4 + 2] = w[(i-nk) * 4 + 2] ^ t2;
        w[i * 4 + 3] = w[(i-nk) * 4 + 3] ^ t3;
        i = i + 1;
    }
}

fn aes_add_round_key(st: ptr, w: ptr, rnd: i64) {
    let i: i64 = 0;
    while i < 16 {
        st[i] = st[i] ^ w[rnd * 16 + i];
        i = i + 1;
    }
}

fn aes_sub_shift(st: ptr, inv: i64) {
    let t: [16] i64 = 0;
    let i: i64 = 0;
    while i < 16 {
        t[i] = st[i];
        i = i + 1;
    }
    if inv == 1 {
        st[0] = AES_ISBOX[t[0]];
        st[4] = AES_ISBOX[t[4]];
        st[8] = AES_ISBOX[t[8]];
        st[12] = AES_ISBOX[t[12]];
        st[1] = AES_ISBOX[t[13]];
        st[5] = AES_ISBOX[t[1]];
        st[9] = AES_ISBOX[t[5]];
        st[13] = AES_ISBOX[t[9]];
        st[2] = AES_ISBOX[t[10]];
        st[6] = AES_ISBOX[t[14]];
        st[10] = AES_ISBOX[t[2]];
        st[14] = AES_ISBOX[t[6]];
        st[3] = AES_ISBOX[t[7]];
        st[7] = AES_ISBOX[t[11]];
        st[11] = AES_ISBOX[t[15]];
        st[15] = AES_ISBOX[t[3]];
    } else {
        st[0] = AES_SBOX[t[0]];
        st[4] = AES_SBOX[t[4]];
        st[8] = AES_SBOX[t[8]];
        st[12] = AES_SBOX[t[12]];
        st[1] = AES_SBOX[t[5]];
        st[5] = AES_SBOX[t[9]];
        st[9] = AES_SBOX[t[13]];
        st[13] = AES_SBOX[t[1]];
        st[2] = AES_SBOX[t[10]];
        st[6] = AES_SBOX[t[14]];
        st[10] = AES_SBOX[t[2]];
        st[14] = AES_SBOX[t[6]];
        st[3] = AES_SBOX[t[15]];
        st[7] = AES_SBOX[t[3]];
        st[11] = AES_SBOX[t[7]];
        st[15] = AES_SBOX[t[11]];
    }
}

fn aes_mix_cols(st: ptr, inv: i64) {
    let c: i64 = 0;
    while c < 4 {
        let a0: i64 = st[c * 4];
        let a1: i64 = st[c * 4 + 1];
        let a2: i64 = st[c * 4 + 2];
        let a3: i64 = st[c * 4 + 3];
        if inv == 1 {
            st[c * 4] = aes_mul(a0, 14) ^ aes_mul(a1, 11) ^ aes_mul(a2, 13) ^ aes_mul(a3, 9);
            st[c * 4 + 1] = aes_mul(a0, 9) ^ aes_mul(a1, 14) ^ aes_mul(a2, 11) ^ aes_mul(a3, 13);
            st[c * 4 + 2] = aes_mul(a0, 13) ^ aes_mul(a1, 9) ^ aes_mul(a2, 14) ^ aes_mul(a3, 11);
            st[c * 4 + 3] = aes_mul(a0, 11) ^ aes_mul(a1, 13) ^ aes_mul(a2, 9) ^ aes_mul(a3, 14);
        } else {
            st[c * 4] = aes_mul(a0, 2) ^ aes_mul(a1, 3) ^ a2 ^ a3;
            st[c * 4 + 1] = a0 ^ aes_mul(a1, 2) ^ aes_mul(a2, 3) ^ a3;
            st[c * 4 + 2] = a0 ^ a1 ^ aes_mul(a2, 2) ^ aes_mul(a3, 3);
            st[c * 4 + 3] = aes_mul(a0, 3) ^ a1 ^ a2 ^ aes_mul(a3, 2);
        }
        c = c + 1;
    }
}

fn aes_block(nk: i64, w: ptr, inp: ptr, outp: ptr) {
    let nr: i64 = nk + 6;
    let st: [16] byte = 0;
    let i: i64 = 0;
    while i < 16 {
        store8(st + i, load8(inp + i));
        i = i + 1;
    }
    aes_add_round_key(st, w, 0);
    let rnd: i64 = 1;
    while rnd < nr {
        aes_sub_shift(st, 0);
        aes_mix_cols(st, 0);
        aes_add_round_key(st, w, rnd);
        rnd = rnd + 1;
    }
    aes_sub_shift(st, 0);
    aes_add_round_key(st, w, nr);
    i = 0;
    while i < 16 {
        store8(outp + i, load8(st + i));
        i = i + 1;
    }
}

fn aes_block_dec(nk: i64, w: ptr, inp: ptr, outp: ptr) {
    let nr: i64 = nk + 6;
    let st: [16] byte = 0;
    let i: i64 = 0;
    while i < 16 {
        store8(st + i, load8(inp + i));
        i = i + 1;
    }
    aes_add_round_key(st, w, nr);
    let rnd: i64 = nr - 1;
    while rnd >= 1 {
        aes_sub_shift(st, 1);
        aes_add_round_key(st, w, rnd);
        aes_mix_cols(st, 1);
        rnd = rnd - 1;
    }
    aes_sub_shift(st, 1);
    aes_add_round_key(st, w, 0);
    i = 0;
    while i < 16 {
        store8(outp + i, load8(st + i));
        i = i + 1;
    }
}

fn aes_ecb_encrypt(nk: i64, key: ptr, data: ptr, len: i64) {
    let w: [240] byte = 0;
    aes_key_expand(nk, key, w);
    let off: i64 = 0;
    while off < len {
        aes_block(nk, w, data + off, data + off);
        off = off + 16;
    }
}

fn aes_ecb_decrypt(nk: i64, key: ptr, data: ptr, len: i64) {
    let w: [240] byte = 0;
    aes_key_expand(nk, key, w);
    let off: i64 = 0;
    while off < len {
        aes_block_dec(nk, w, data + off, data + off);
        off = off + 16;
    }
}

fn aes_ctr(nk: i64, key: ptr, nonce: ptr, data: ptr, len: i64) {
    let w: [240] byte = 0;
    aes_key_expand(nk, key, w);
    let ctr: [16] byte = 0;
    let ks: [16] byte = 0;
    let i: i64 = 0;
    while i < 16 {
        store8(ctr + i, load8(nonce + i));
        i = i + 1;
    }
    let off: i64 = 0;
    while off < len {
        aes_block(nk, w, ctr, ks);
        let j: i64 = 0;
        while j < 16 {
            if off + j < len {
                store8(data + off + j, load8(data + off + j) ^ load8(ks + j));
            }
            j = j + 1;
        }
        j = 15;
        while j >= 8 {
            let v: i64 = (load8(ctr + j) + 1) & 255;
            store8(ctr + j, v);
            if v != 0 {
                j = -1;
            }
            j = j - 1;
        }
        off = off + 16;
    }
}

# Random123 cross-test profile.
CROSS_BUILD_STEP=test

CROSS_BUILD_JOBS=4

# Maximum build time per target, in seconds.
CROSS_BUILD_TIMEOUT=1800

# Maximum run time per test binary, in seconds.
CROSS_TIMEOUT=600

# Keep cross runs static and linked; WASI lacks shared objects and `dlopen`.
CROSS_BUILD_ARGS=(-Dlinkage=static -Druntime=false)
module benchmark.math;

private  {
  import benchmark.registry;
  import graphics.core.edgebuilder : fastSqrt;
  import graphics.math.rounding;
}

static this() {
  registerBenchmark!(runMath)();
}

void benchFastSqrt() {
  real sum = 0.0;
  for (auto i = 0; i < 1_000_000; ++i) {
    sum += fastSqrt(i);
  }
}

void benchSSETruncate() {
  uint sum;
  for (float f = 0.0f; f < 1e6f; f+=1.0f) {
    sum += SSETruncate(f);
  }
}

void benchStdMathTruncate() {
  uint sum;
  for (float f = 0.0f; f < 1e6f; f+=1.0f) {
    sum += stdMathTruncate(f);
  }
}

void benchStdMathLRInt() {
  uint sum;
  for (float f = 0.0f; f < 1e6f; f+=1.0f) {
    sum += cast(int)std.math.lrint(f);
  }
}

void runMath(BenchmarkReporter reporter) {
  reporter.bench!(benchFastSqrt)();
  reporter.bench!(benchStdMathTruncate)();
  reporter.bench!(benchSSETruncate)();
  reporter.bench!(benchStdMathLRInt)();
}

module benchmark.main;

import std.algorithm, std.array, std.stdio;
import benchmark.registry, benchmark.reporter;

import graphics;

import benchmark.matrix;
import benchmark.wavelet;

int main(string[] argv) {
  scope auto reporter = new BenchmarkReporter(10);

  if (argv.length > 1) {

    if (!argv[1..$].find("-l").empty || !argv[1..$].find("--list").empty) {
      auto benchmarks = allBenchmarks();
      foreach(ref benchTup; benchmarks) {
        writeln(benchTup[0]);
      }
      return 0;
    }
  }
  // auto benchmarks = allBenchmarks();
  auto benchmarks = argv.length > 1 ? selectBenchmarks(argv[1]) : excludeBenchmarks("");

  foreach(ref testTup; benchmarks) {
    reporter.info("--------------------Run BenchMarkSuite %s--------------------", testTup[0]);
    testTup[1](reporter);
  }
  return 0;
}

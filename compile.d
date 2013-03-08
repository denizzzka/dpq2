#!/usr/bin/rdmd
module compile;

import dmake;

enum DPQ_ONAME = "dpq2";
enum EXAMPLE_ONAME = "example";
enum UNITTEST_ONAME = "unittest";

string cleanupCommands()
{
	version(Windows)
	{
		return "del *.obj *.lib && del docs && del "~EXAMPLE_ONAME~".exe "~UNITTEST_ONAME~".exe";
	} else
	{
		return "rm -rf *.o *.a && rm -rf docs && rm -rf "~EXAMPLE_ONAME~" "~UNITTEST_ONAME;
	}
}

static this()
{
	// Static libpq bindings
	addCompTarget("static", "./", DPQ_ONAME, BUILD.LIB);
	addSource("./src/dpq2");
	addCustomFlags("-version=BINDINGS_STATIC");

	// Dynamic libpq bindings
	addCompTarget("dynamic", "./", DPQ_ONAME, BUILD.LIB);
	addSource("./src/dpq2");
	addCustomFlags("-version=BINDINGS_DYNAMIC");

	// Clean
	addCompTarget("clean", "", "", BUILD.NONE);
	addCustomCommand(&cleanupCommands);

	// Example
	addCompTarget("example-dynamic", "./", EXAMPLE_ONAME, BUILD.APP);
	addDependTarget("dynamic");
	addSingleFile("./src/example.d");
	addCustomFlags("-version=BINDINGS_DYNAMIC");

	addCompTarget("example-static", "./", EXAMPLE_ONAME, BUILD.APP);
	addDependTarget("static");
	addSingleFile("./src/example.d");
	addCustomFlags("-version=BINDINGS_STATIC -L-lpq -L-lcom_err");

	// Unittesting
	addCompTarget("unittest-dynamic", "./", UNITTEST_ONAME, BUILD.APP);
	addDependTarget("dynamic");
	addSingleFile("./src/unittests_main.d");
	addCustomFlags("-version=BINDINGS_DYNAMIC -unittest");

	addCompTarget("unittest-static", "./", UNITTEST_ONAME, BUILD.APP);
	addDependTarget("static");
	addSingleFile("./src/unittests_main.d");
	addCustomFlags("-version=BINDINGS_STATIC -unittest -L-lpq -L-lcom_err");

	// Docs
	addCompTarget("docs", "./", DPQ_ONAME, BUILD.LIB);
	addSource("./src/dpq2");
	addCustomFlags("-D -Dd./docs");
	addCustomFlags("-version=BINDINGS_DYNAMIC");
}

int main(string[] args)
{
	checkProgram("dmd", "Cannot find dmd to compile project! You can get it from http://dlang.org/download.html");
	// Start parsing
	return proceedCmd(args);
}
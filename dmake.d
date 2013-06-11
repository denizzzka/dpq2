//          Copyright Gushcha Anton 2012.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

// Written in the D programming language.
/**
*	Version: 1.02
*	License: Boost Version 1.0
*
*	This module simplifies crossplatform compilation for multifile projects. Module provides
*	functions to control dependencies written in no D languages and can check existance
*	of needed instruments and libraries in system. Supported compile targets: applications,
*	static libraries (.a .lib), shared libraries (.so .dll).
*	
*	Bugs: linux shared libraries generation at x86_64 seemed to be broken; static dll linkage broken
*
*	Example:
*	------------
*	import dmake;
*	
*	// main application out dependencies	
*	string[string] appDepends;
*
*	// set up appDepends
*	static this()
*	{
*		appDepends = [
*			"outLib1" : "../deps/outLib1"
*		];	
*	}
*
*	// Function to compile outlib if necessary
*	void compileOutLib1(string path)
*	{
*		version(Windows)
*		{
*			// some shell calls ...
*		}
*		version(linux)
*		{
*			// you can check instrument existance
*			checkProgram("make", "Cannot find make, you can get it from your standart source repository!");
*			// some shell calls ...		
*		}
*	}
*	
*	int main(string[] args)
*	{
*		// your library
*		addCompTarget("mylib", "../lib", "mylib", BUILD.LIB);
*		addSource("../src/mylib");
*		
*		// Adding main application
*		addCompTarget("app", "../bin", "main", BUILD.APP);
*		addSource("../src/app");
*		setDependPaths(appDepends);
*		
*		// Adding to app dependency outLib1 files 
*		// Windows: ../deps/outLib1/lib/file1.lib, ../deps/outLib1/lib/file2.lib
*		// GNU/Linux: ../deps/outLib1/lib/libfile1.a, ../deps/outLib1/lib/libfile2.a
*		// with import search file ../deps/outLib1/import
*		// if files cannot be found, delegate compileOutLib1 called.
*		addLibraryFiles("outLib1", "lib", ["file1", "file2"], ["import"] , &compileOutLib1);
*
*		// adding your libary as app dependency
*		addDependTarget("mylib");
*
*		// Begin actual compilation
*		// arguments 'all debug' will compile all targets in debug mode
*		// argument  'mylib' will compile only mylib in release mode
*		// arguments 'app release' will compile first mylib, then app in release mode
*		return proceedCmd(args);
*	}
*	------------
*/
module dmake;

import std.array;
import std.file;
import std.stdio;
import std.process;
import std.traits;
import std.algorithm;
import std.exception;
import std.string;

version(Windows)
{
	enum TARGET_EXT = ".exe";
	enum ADDITIONAL_FLAGS = "";
	enum LIB_PREFIX = "";
	enum LIB_EXT = ".lib";
	enum SLIB_EXT = ".dll";

	// getting def file content for dll
	string getDefFile(string name)
	{
		return 
`LIBRARY "`~name~`" 
EXETYPE NT 
SUBSYSTEM WINDOWS 
CODE SHARED EXECUTE 
DATA WRITE`;
	}

}
version(linux)
{
	enum TARGET_EXT = "";
	enum ADDITIONAL_FLAGS = "-L-ldl";
	enum LIB_PREFIX = "lib";
	enum LIB_EXT = ".a";
	enum SLIB_EXT = ".so";
}

enum BUILD
{
	APP,
	LIB,
	SHARED,
	NONE // Compiler call will not be perfomed
}

enum MODEL
{
	X86_64,
	X86
}

/// checkProgram
/**
*	Function helps check program availability through system shell. 
*	Program $(D name) should be typed without extention as if you typed it
*	in shell. If function doesn't find program, compilation stops and
*	message $(D msg) displays to the user. Usefull to put into $(D msg) informathion
*	where you can get needed program.
*/
void checkProgram(string name, string msg)
{
	enforce(programExists(name), "Compilation stopped: "~msg);
}

/// addCompTarget
/**
*	Add compilation target with $(D name) and sets to current target. Almost functions operate with
*	seted current target. To switch within targets use $(D setCurrTarget). String $(D outdir) sets 
*	output directory where finally binary file with name $(D name) will be put. Enum value $(D type)
*	determines the output type. BUILD.APP - application, BUILD.LIB - static library, BUILD.SHARED - 
*	shared library (.dll or .so). All library prefixes and file extentions will be appended automatically.
*
*	Example:
*	--------
*	// Setting up simple application.
*	// output file will be named as main.exe (Win) or main (GNU/Linux)
*	addCompTarget("app", "./bin", "main", BUILD.APP);
*
*	// Setting up simple library
*	// output file will be named as test.lib (Win) or libtest.a (GNU/Linux)
*	addCompTarget("lib", "./lib", "test", BUILD.LIB);
*	--------
*/
void addCompTarget(string name, string outDir, string outName, BUILD type = BUILD.APP)
{
	enforce(name != "debug" && name != "release", "Target name "~name~" is forbidden, please use another one.");
	auto ret = new CompilationTarget(outName, outDir, type);

	if(!exists(outDir))
		mkdirRecurse(outDir);

	mCurrTarget = ret;
	mTargets[name] = ret;
}

/// addDependTarget
/**
*	This function helps order targets compilation. Current compile target
*	will compile after target $(D name). If circular dependencies detected,
*	compilation will fail with a message. If $(D linkStatic) is true and
*	target $(D name) is shared library, import library will be linked to app,
*	else does nothing.
*	
*	Example:
*	--------
*	addCompTarget("library", ".", "somelib", BUILD.LIB);
*	addCompTarget("app", ".", "main", BUILD.APP);
*	//...
*	// library 
*	return proceedCmd(args);
*	--------
*/
void addDependTarget(string name, bool linkStatic = false)
{
	if(name !in mTargets || mTargets[name] == mCurrTarget)
		return;

	auto target = mTargets[name];
	if(target.type == BUILD.LIB)
	{
		if(target.generateHeaders)
		{
			mCurrTarget.addFlags ~= "-I"~target.headersDir~" ";
		}
		foreach(s; target.sourcePaths)
			mCurrTarget.addFlags ~= "-I"~s~" ";

		mCurrTarget.addFlags ~= target.finalname~" ";
	}
	if(target.type == BUILD.SHARED && linkStatic)
	{
		enforce(false, "Dll static linkage broken http://d.puremagic.com/issues/show_bug.cgi?id=6019, you can add 'extern(C) int D3MYDLLMODULE12__ModuleInfoZ;' to your file, but import library will cause runtime error about 'wrong image'. Use C-style interfaces and dynamic linking (also look at Derelict3 as bindings for a lot of libs).");

		if(target.generateHeaders)
		{
			mCurrTarget.addFlags ~= "-I"~target.headersDir~" ";
		} else
			writeln("Target shared libary "~name~" doesn't have interface files to link. Use setHeadersGeneration to setup this.");
		
		mCurrTarget.addFlags ~= target.outDir~"/"~LIB_PREFIX~target.outName~LIB_EXT~" ";
	}
	mCurrTarget.dependTargets~=target;
}

/// setHeadersGeneration
/**
*	Sets header generation fo current compilation target, also
*	known as interface (.di) files. Sets headers output folder to
*	$(D dir)
*/
void setHeadersGeneration(string dir)
{
	mCurrTarget.generateHeaders = true;
	mCurrTarget.headersDir = dir;
}

/// addCustomFlags
/**
*	Adds string $(D flags) to compiler input for current target.
*/
void addCustomFlags(string flags)
{
	mCurrTarget.addFlags ~= " "~flags~" ";
}

/// setCompilationModel
/**
*	Explicitly sets current target $(D model) MODEL.X86_64 or MODEL.X86.
*/
void setCompilationModel(MODEL model)
{
	mCurrTarget.buildModel = model;
}

/// setDocsGeneration
/**
*	Sets documentation generation for current compilation target
*	and sets output docs dir as $(D dir).
*/
void setDocsGeneration(string dir)
{
	mCurrTarget.generateDocs = true;
	mCurrTarget.docsDir = dir;
}

/// setCurrTarget
/**
*	Sets current compilation target to $(D name). All other functions
*	will operate with this target. If target wasn't registered, throws
*	exception.
*/
void setCurrTarget(string name)
{
	if( name in mTargets )
		mCurrTarget = mTargets[name];
	else
		throw new Exception("Target "~name~" wasn't registered!");
}

/// getCurrentTarget
/**
*	Returns compilation target assigned to current target.
*/
CompilationTarget getCurrentTarget()
{
	return mCurrTarget;
}

/// setDependPaths
/**
*	Registeres dependencies passed with string massive $(D paths) for
*	current compilation target. $(D paths) keys used for dependencies names
*	and values used for dependencies relative paths. Needs to be called
*	before $(D addLibraryFiles) or $(D checkSharedLibraries).
*/
void setDependPaths(string[string] paths)
{
	mCurrTarget.dependPaths = paths;
}

/// existsAll
/**
*	Checks if all files from list $(D arr) exists.
*/
private bool existsAll(string[] arr)
{
	bool res = true;
	foreach(s; arr)
		res = res && exists(s);
	return res;
}

// addLibraryFiles
/**
*	Binds library files listed in $(D names) without extentions (*.a, *.lib) and prefixes (lib*) to dependency $(D lib).
*	$(D filesPath) is relative path from dependency root path where script should find library files. Each entry from 
*	$(D importPaths) will be passed to compiler as search library sources path. If function isn't able to find all listed
*	files, it runs delegate $(D compileDelegate) which should try to compile those files, function passes to $(D compileDelegate)
*	dependency root path. If boolean value $(D tryAgain) switched to $(D true), function will retry adding library files.
*
*	Example:
*	----------
*	addCompTarget("app", ".", "main", BUILD.APP);
*	setDependPaths(["library": "../lib"]);
*
*	addLibraryFiles("library", "../lib/bin", ["first", "second"], ["import"],
*		(string libPath)
*		{
*			// Here some code to compile library
*		});
*	----------
*/
void addLibraryFiles(T)(string lib, string filesPath, string[] names, string[] importPaths, T compileDelegate, bool tryAgain = true)
	if( (isFunctionPointer!T || isDelegate!T))
{
	assert(lib in mCurrTarget.dependPaths, "Dependency name "~lib~" wasn't registered!");

	static assert(__traits(compiles, `compileDelegate("somelib");`), "Delegate compileDelegate must get only one paramater. Format: void function(string libpath)");
	if (names.empty) return;

	auto newNames = names.dup;

	foreach(ref s; newNames)
		s = mCurrTarget.dependPaths[lib]~"/"~filesPath~"/"~LIB_PREFIX~s~LIB_EXT;

	if (!existsAll(newNames))
	{
		// Компилируем
		version(Windows)
			mCurrTarget.convertWinNames();

		string libPath = mCurrTarget.dependPaths[lib];

		compileDelegate(libPath);
		if(!tryAgain) 
		{
			writeln("Compilation failed: Library "~lib~" wasn't compiled!");
			return;
		}
	}

	foreach(s; importPaths)
		mCurrTarget.addFlags ~= `-I`~mCurrTarget.dependPaths[lib]~"/"~s~" ";
	foreach(s; newNames)
		mCurrTarget.addFlags ~= s~" ";
}


/// checkSharedLibraries
/**
*	Some dependencies compiled to shared library files (.dll or .so) and they cannot be directly added to compilation target. Function checks
*	existence of shared library files listed by $(D names) without prefixes (lib) and extentions (.so, .dll) for dependency $(D lib) added before with
*	$(D setDependPaths). If function cannot find $(D names) at out directory or system paths, then it calls delegate $(D compileDelegate) with name of root
*	dependency dir. Delegate should try to compile dependency and if $(D checkAgain) flag setted to $(D true), function will recheck $(D names). If 
*	$(D findInSystem) setted to $(D true), function will also try find libraries in system paths.
*
*	Example:
*	---------
*	addCompTarget("app", ".", "main", BUILD.APP);
*	setDependPaths(["library": "../lib"]);
*
*	addLibraryFiles("library", ["first", "second"],
*		(string libPath)
*		{
*			// Here some code to compile library
*		});
*	---------
*/
void checkSharedLibraries(T)(string lib, string[] names, T compileDelegate, bool checkAgain = true, bool findInSystem = false)
	if( (isFunctionPointer!T || isDelegate!T))
{
	static assert(__traits(compiles, `compileDelegate("somelib");`), "Delegate compileDelegate must get only one paramater. Format: void function(string libpath)");
	if (names.empty) return;

	foreach(ref s; names)
		s = mCurrTarget.outDir~"/"~LIB_PREFIX~s~SLIB_EXT;

	bool findedInSystem = false;
	if(findInSystem)
	{
		foreach(name; names)
			if( sharedLibraryExists(name) )
			{
				findedInSystem = true; 
				break;
			}
	}

	if (!existsAll(names) && !findedInSystem && compileDelegate !is null)
	{
		// Компилируем
		version(Windows)
			mCurrTarget.convertWinNames();
		
		string libPath = mCurrTarget.dependPaths[lib];

		compileDelegate(libPath);
		if(checkAgain && !existsAll(names)) 
		{
			writeln("Compilation failed: Shared library "~lib~" wasn't compiled!");
			return;
		}
	}
}

/// addSource
/**
*	Adding all *.d and *.di files from directory $(D dir) to current compilation target. All subdirectories and
*	links recursively will be passed.
*
*	Example:
*	---------
*	setCurrTarget("app");
*	// All files and subdirs will be passed
*	addSource("../src");
*	--------- 
*/
void addSource(string dir)
{
	if (dir.empty) return;
	SpanMode mode = SpanMode.breadth;

	mCurrTarget.sourcePaths ~= dir;
	mCurrTarget.addFlags ~= "-I"~dir~" ";
	auto direntries = dirEntries(dir, mode, true);

	auto list = filter!`endsWith(a.name,".d")`(direntries);
	foreach(path; list)
	{
		mCurrTarget.addFlags ~= path.name~" "; 
	}

	direntries = dirEntries(dir, mode, true);
	auto list2 = filter!`endsWith(a.name,".di")`(direntries);
	foreach(path; list2)
	{
		mCurrTarget.addFlags ~= path.name~" "; 
	}

}

/// addSingleFile
/**
*	Occasionally situation occurs when needed add only some files to compilation target and $(D addSource) doesn't suit.
*	Then you call this function with exact source $(D name), which will be added to current compilation target.
*	
*	Example:
*	---------
*	setCurrTarget("app");
*	addSingleFile("./src/main.d");
*	addSingleFile("../scripts/somemodule.d");
*	---------
*/
void addSingleFile(string name)
{
	if(!exists(name))
	{
		writeln("File "~name~" doesn't exist!");
		return;
	}
	mCurrTarget.addFlags ~= name~" ";
}

/// addCustomCommand
/**
*	Adds shell command which will be called before compiling. Usefull with BUILD.NONE to
*	create cleanup targets for instance.
*
*	Example:
*	----------
*	setCurrTarget("app");
*	addCustomCommand((){return "rm -rf *.a *.o";});
*	----------
*/
void addCustomCommand(string function() comm)
{
	mCurrTarget.customCommands ~= comm;
}

/// compileTarget
/**
*	Sends to compilation target with name $(D target). This function doesn't consider compilation dependencies, see
*	$(D proceedCmd). If function cannot find target, exception occured.
*/
void compileTarget(string target)
{
	if( target in mTargets)
	{
		compileTarget(mTargets[target]);
	} else
		throw new Exception("Target "~target~" isn't registered!");
}

/// compileTarget
/**
*	Inner implemetation of $(D compileTarget(string target)).
*/
private void compileTarget(ref CompilationTarget target)
{
	string comm = "dmd ";
	string sharedLib, oldname;
	with(target)
	{
		final switch(type)
		{
			case BUILD.APP:
			{
				outName~= TARGET_EXT;
				break;
			}
			case BUILD.LIB:
			{
				outName = LIB_PREFIX~outName~LIB_EXT;
				comm ~= "-lib ";
				break;
			}
			case BUILD.SHARED:
			{
				oldname = outName;
				sharedLib = LIB_PREFIX~outName~SLIB_EXT;
				outName = LIB_PREFIX~outName~LIB_EXT;
				break;
			}
			case BUILD.NONE:
			{
				break;
			}
		}

		if(generateHeaders)
		{
			addFlags~="-Hd"~headersDir~" ";
		}

		if(debugMode)
			comm ~= "-unittest -debug -gc -profile ";
		else
			comm ~= "-release -inline -O ";

		final switch(buildModel)
		{
			case MODEL.X86_64:
			{
				comm ~= "-m64 ";
				break;
			}
			case MODEL.X86:
			{
				comm ~= "-m32 ";
				break;
			}
		}

		if(!exists(outDir))
			mkdirRecurse(outDir);

		if(customCommands.length > 0)
		{
			foreach(func; customCommands)
				if(system(func()) != 0)
				{
					writeln("Custom commands failed. Compilation stopped.");
					return;
				}
		}

		if(type == BUILD.NONE)
			return;

		if(type!=BUILD.SHARED)
		{
			comm ~= "-of"~outDir~"/"~outName~" "~ADDITIONAL_FLAGS~" "~addFlags;
			version(Windows)
				comm = replace(comm, "/", "\\");
			system(comm);
		} else
		{
			comm ~= "-od"~outDir~" -of"~outDir~"/"~sharedLib~" "~ADDITIONAL_FLAGS~" "~addFlags;
			version(linux)
			{
				comm ~= "-lib -c -fPIC ";
				system(comm);
				comm = "ld -shared -o "~outDir~"/"~sharedLib~" "~outDir~"/"~outName~" -lrt -lphobos2 -lpthread";
				system(comm);
			}
			version(Windows)
			{
				comm = replace(comm, "/", "\\");
				// checking def file
				string defName = outDir~"\\"~oldname~".def";
				if(!exists(defName))
				{
					auto defFile = new File(defName, "w");
					defFile.writeln(getDefFile(outName));
					defFile.close();
				}

				comm ~= "-L/IMPLIB "~defName~" ";
				system(comm);
				// moving import library

				string importLib = outDir~"\\"~LIB_PREFIX~oldname~LIB_EXT;
				if (exists(importLib))
					remove(importLib);
				rename(".\\"~LIB_PREFIX~oldname~LIB_EXT,importLib);
			}
		}

	}
}

/// proceedCmd
/**
*	Parses cmd input arguments and compile specified target. First argument is target name or special word 'all', 
*	which compile all targets. Second argument is compile mode: debug or release; it can be not passed, then release
*	mode will be used. Function detects tangled arguments, thats why 'debug' and 'release' target names restricted.
*	This function needs to be called last and returns standart system return code. Function will detect all input
*	errors and show error reasons. Targets compiles in dependency order, if circular dependencies occures compilation
*	will be stopped and message will be shown.
*
*	Example:
*	--------
*	int main(string[] args)
*	{
*		// First set up all targets and dependencies
*		//...
*		
*		// Here begins actual compilation
*		return proceedCmd(args);
*	}
*	--------
*/
int proceedCmd(string[] args)
{
	static string help = `Compilation script usage:
	script <target/all> [debug/release]`;
	if(args.length < 2 || args.length > 3)
	{
		writeln(help);
		return 1;
	}

	// switching args if tangled
	if((args[1] == "debug" || args[1] == "release") && args.length == 3)
	{
		swap(args[1], args[2]);
	}

	if(args[1] !in mTargets && args[1] != "all")
	{
		writeln("Cannot find target "~args[1]~". Try one of: ",mTargets.keys);
		return 1;
	}

	if(args.length > 2)
		if(args[2] != "debug" && args[2] != "release")
		{
			writeln(help);
			return 1;
		}
		else if(args[2] == "debug")
			if(args[1]!="all")
				mTargets[args[1]].debugMode = true;
			else
				foreach(tar; mTargets)
					tar.debugMode = true;

	if(args[1]!="all")
	{
		auto target = mTargets[args[1]];
		if(!target.dependTargets.empty)
		{
			writeln("Compiling "~args[1]~" dependencies...");
			foreach(dep;getSortedTargets(target.dependTargets))
				if( !exists(dep.finalname) )
					compileTarget(dep);
		}
		writeln("Compiling "~args[1]~"...");
		compileTarget(mTargets[args[1]]);
		writeln("Finished.");
	}
	else
	{
		auto ntars = getSortedTargets();

		foreach(ntar; ntars)
		{
			writeln("Compiling "~ntar.name~"...");
			compileTarget(ntar.tar);
			writeln("Finished.");
		}
	}
	return 0;
}


/// programExists
/**
*	Checks availability of program $(D name) (without extention) through system shell.
*	Doesn't support alias names. 
*
*	Example:
*	--------
*	programExists("make");
*	programExists("gcc");
*
*	// Windows standart shell names examples
*	programExists("chkdisk");
*	programExists("del");
*
*	// Checks local program
*	programExists("myProg");
*	--------
*/
bool programExists(string name)
{
	name = toLower(name);
	// forming full name
	version(Windows)
		name ~= ".exe";

	// search in local dir
	if(exists(name)) return true;

	version(Windows)
	{
		enum DELIM = ";";
		enum SLASH = "\\";

		// Standart windows shell
		string[] wndShell = [
			"assoc", "attrib", "break", "bcdedit", "cacls", "call", "cd",
			"chcp", "chdir", "chkdsk", "chkntfs", "cls", "cmd", "color",
			"comp", "compact", "convert", "copy", "date", "del", "dir",
			"diskcomp", "diskcopy", "diskpart", "doskey", "driverquery",
			"echo", "endlocal", "erase", "exit", "fc", "find", "findstr",
			"for", "format", "fsutil", "ftype", "goto", "gpresult", "graftabl",
			"help", "icacls", "if", "label", "md", "mkdir", "mklink", "mode",
			"more", "move", "openfiles", "path", "pause", "popd", "print",
			"print", "promt", "pushd", "rd", "recover", "rem", "ren", "rename",
			"replace", "rmdir", "robocopy", "set", "setlocal", "sc", "schtasks",
			"shift", "shutdown", "sort", "start", "subst", "systeminfo", "tasklist",
			"taskkill", "time", "title", "tree", "type", "ver", "verify",
			"vol", "xcopy", "wmic"
		];

		foreach(cmd; wndShell)
			if(cmd~".exe" == name)
				return true;
	}
	version(linux)
	{
		enum DELIM = ":";
		enum SLASH = "/";
	}

	// search in environment
	auto paths = environment["PATH"];
	foreach(path; splitter(paths, DELIM))
		if(exists(path~SLASH~name))
			return true;	

	return false;
}

/// sharedLibraryExists
/**
*	Checks existance of shared library (.so or .dll) with $(D name) (without prefixes and extention) 
*	in system library search paths.
*	
*	Example:
*	---------
*	// Windows examples
*	sharedLibraryExists("kernel32");
*
*	// Some linux library
*	sharedLibraryExists("freeimage-3.15.4");
*	---------
*/
bool sharedLibraryExists(string name)
{
	auto searchDirs = new string[0];

	version(Windows)
	{
		// we need check system dirs
		import core.sys.windows.windows;

		enum BUFF_SIZE = 512u;
		auto buff = new char[BUFF_SIZE];
		auto blength = GetSystemDirectoryA(buff.ptr, BUFF_SIZE);
		
		// If path doesn't fit buff Oo
		if (blength > BUFF_SIZE)
		{
			buff = new char[blength];
			GetSystemDirectoryA(buff.ptr, blength);
		}

		searchDirs ~= buff[0..blength].idup;

		enum DELIM = ";";
		enum SLASH = "\\";
	}
	version(linux)
	{
		// all paths written in PATH
		enum DELIM = ":";
		enum SLASH = "/";
	}

	// search in environment
	auto paths = environment["PATH"];
	foreach(path; splitter(paths, DELIM))
		searchDirs ~= path;

	writeln(searchDirs);
	foreach(path; searchDirs)
		if(exists(path~SLASH~LIB_PREFIX~name~SLIB_EXT))
			return true;
	
	return false;
}

//=====================================================
/// CompilationTarget
/**
*	Usually you don't need to work with this class directly. It's temporaly storage of all compilation settings.
*/
class CompilationTarget
{
	string					outName;
	string					outDir;
	string[string] 			dependPaths;
	string[]				sourcePaths;
	CompilationTarget[]		dependTargets;
	string					addFlags;
	bool					debugMode = false;
	BUILD					type;

	bool					generateHeaders = false;
	string					headersDir;

	bool					generateDocs	= false;
	string					docsDir;

	MODEL					buildModel;
	string function()[]		customCommands;

	this(string pOutName = "", string pOutDir = "", BUILD pType = BUILD.APP)
	{
		outName = pOutName;
		outDir = pOutDir;
		type = pType;

		dependTargets = new CompilationTarget[0];
		sourcePaths = new string[0];
		customCommands = new string function()[0];

		version(X86_64)
			buildModel = MODEL.X86_64;
		version(X86)
			buildModel = MODEL.X86;
	}

	version(Windows)
	{
		/// convertWinNames
		/**
		*	Replaces primary slashes with backslashes in all important fields.
		*/
		void convertWinNames()
		{
			void replaceSlashes(ref string str)
			{
				str = replace(str, "/", "\\");
			}

			replaceSlashes(outName);
			replaceSlashes(outDir);

			foreach(ref str; dependPaths)
				replaceSlashes(str);
		}
	}

	// finalname
	/**
	*	Returns final relative out file name with extentions and prefixes.
	*/
	string finalname() @property
	{
		string tempName;
		final switch(type)
		{
			case BUILD.APP:
			{
				tempName = outName~TARGET_EXT;
				break;
			}
			case BUILD.LIB:
			{
				tempName = LIB_PREFIX~outName~LIB_EXT;
				break;
			}
			case BUILD.SHARED:
			{
				tempName = LIB_PREFIX~outName~SLIB_EXT;
				break;
			}
			case BUILD.NONE:
			{
				tempName = "";
				break;
			}
		}
		return outDir~"/"~tempName;
	}
}

private CompilationTarget[string] mTargets;
private CompilationTarget mCurrTarget;

// Creating dummy target to prevent crashes with incorrect usage
static this()
{
	mCurrTarget = new CompilationTarget;
}

private struct NamedTarget
{
	CompilationTarget tar;
	string name;

	this(string tname, CompilationTarget target)
	{
		tar = target;
		name = tname;
	}
}

// getSortedTargets
/*
*	Constructing sorted list of targets by dependency relation. This version takes targets from $(D mTargets).
*/
private NamedTarget[] getSortedTargets()
{
	auto ret = new NamedTarget[0];

	foreach(key, val; mTargets)
		ret ~= NamedTarget(key, val);

	bool isDepend(ref NamedTarget tar1, ref NamedTarget tar2)
	{
		foreach(dep; tar1.tar.dependTargets)
			if(dep == tar2.tar)
				return true;
		return false;
	}

	try
	{
		sort!(isDepend)(ret);
		reverse(ret);
	}
	catch(Exception e)
	{
		throw new Exception("Failed to form dependencies list! Check for circular dependencies!");
	}

	return ret;
}

// getSortedTargets
/*
*	Constructing sorted list of targets by dependency relation. This version is supplied with targets $(D deps).
*/
private CompilationTarget[] getSortedTargets(CompilationTarget[] deps)
{
	auto ret = deps.dup;

	bool isDepend(CompilationTarget tar1, CompilationTarget tar2)
	{
		foreach(dep; tar1.dependTargets)
			if(dep == tar2)
				return true;
		return false;
	}

	try
	{
		sort!(isDepend)(ret);
		reverse(ret);
	}
	catch(Exception e)
	{
		throw new Exception("Failed to form dependencies list! Check for circular dependencies!");
	}

	return ret;	
}
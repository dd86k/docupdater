#!/bin/env rdmd

/**
 * Script that automates the process of keeping documentation up to date.
 * 
 * Author: dd86k
 * Copyright: None
 * License: Unlicense
 */
module docupdater;

import std.stdio, std.getopt, std.file, std.path;
import std.string : toStringz;
import core.stdc.stdlib : system;

enum VERSION = "0.0.0";
enum E_ERROR = "[error] ";
enum E_WARN = "[warn] ";
enum E_INFO = "[info] ";

version (Windows) {
	enum NULL_REDIRECT = " > nul 2>&1";
} else {
	enum NULL_REDIRECT = " > /dev/null 2>&1";
}
enum DMD_VERSION = "dmd --version"	~ NULL_REDIRECT;
enum GDC_VERSION = "gdc --version"	~ NULL_REDIRECT;
enum LDC_VERSION = "ldc2 --version"	~ NULL_REDIRECT;
enum DUB_VERSION = "dub --version"	~ NULL_REDIRECT;
enum GIT_VERSION = "git --version"	~ NULL_REDIRECT;

enum Compiler { none, dmd, gdc, ldc }
Compiler detectedCompiler;

enum BuildType { dubDdox, file }
struct Entry {
	string name;
	BuildType type;
	Compiler prefCompiler;	/// Preferred compiler for project
	string location;	/// Repository
	string source;	/// What file/folder to copy
}

//
// Configuration
//

immutable Entry[] entries = [
	{
		"alicedbg",
		BuildType.dubDdox, Compiler.none,
		"https://git.dd86k.space/git/dd86k/alicedbg.git",
		"docs"
	},
	{
		"ddcpuid",
		BuildType.dubDdox, Compiler.none,
		"https://git.dd86k.space/git/dd86k/ddcpuid.git",
		"docs"
	},
	{
		"sha3-d",
		BuildType.dubDdox, Compiler.none,
		"https://github.com/dd86k/sha3-d.git",
		"docs"
	},
	{
		"docupdater",
		BuildType.file, Compiler.none,
		"https://git.dd86k.space/git/dd86k/docupdater.git",
		"docupdater.d"
	}
];

string formatFile(Compiler compiler, string input, string name) {
	import std.format : format;
	string fmt = void;
	with (Compiler)
	final switch (compiler) {
	case dmd: fmt = "dmd %s -Df%s.html"~NULL_REDIRECT; break;
	case gdc: fmt = "gdc %s -Df%s.html"~NULL_REDIRECT; break;
	case ldc: fmt = "ldc2 %s --Df=%s.html"~NULL_REDIRECT; break;
	case none: return formatFile(detectedCompiler, input, name);
	}
	return format(fmt, input, name);
}
int generateDoc(ref immutable(Entry) entry, string cacheDir, string outDir) {
	string targetDir = void;
	string sourceDir = void;
	string command = void;
	int e = void;
	
	if (exists(entry.name)) {
		writeln(E_INFO~"Updating entry");
		chdir(entry.name);
		command = "git pull -p"~NULL_REDIRECT;
		if ((e = system(command.toStringz)) != 0) goto L_EXIT;
	} else {
		writeln(E_INFO~"Cloning entry");
		command = "git clone "~entry.location~NULL_REDIRECT;
		if ((e = system(command.toStringz)) != 0) return e;
		chdir(entry.name);
	}
	
	writeln(E_INFO~"Generating documentation");
	
	with (BuildType)
	final switch (entry.type) {
	case dubDdox:
		if ((exists("dub.sdl") || exists("dub.json")) == false) {
			stderr.writeln(E_ERROR~"Missing DUB definition");
			e = 10;
			goto L_EXIT;
		}
		
		try {
			if (exists(entry.source))
				rmdirRecurse(entry.source);
		} catch (Exception ex) {
			stderr.writeln(E_ERROR, ex.msg);
			e = 11;
			goto L_EXIT;
		}
		
		command = "dub build -b ddox"~NULL_REDIRECT;
		system(command.toStringz);
		
		sourceDir = buildPath(cacheDir, entry.name, entry.source);
		if (exists(sourceDir) == false) {
			stderr.writeln(E_ERROR~"Source folder does not exist");
			e = 12;
			goto L_EXIT;
		}
		
		targetDir = buildPath(outDir, entry.name);
		try {
			if (exists(targetDir))
				rmdirRecurse(targetDir);
			mkdir(targetDir);
		} catch (Exception ex) {
			stderr.writeln(E_ERROR, ex.msg);
			e = 13;
			goto L_EXIT;
		}
	
		writeln(E_INFO~"Copying files");
		version (Windows)
			command = "copy "~sourceDir~`\* `~targetDir~NULL_REDIRECT;
		else
			command = "cp "~sourceDir~"/* "~targetDir~NULL_REDIRECT;
		if ((e = system(command.toStringz)) != 0) goto L_EXIT;
		break;
	case file:
		command = formatFile(entry.prefCompiler, entry.source, entry.name);
		if ((e = system(command.toStringz)) != 0) goto L_EXIT;
		
		try {
			string file = entry.name~".html";
			copy(file, buildPath(outDir, file));
		} catch (Exception ex) {
			stderr.writeln(E_ERROR, ex.msg);
			e = 20;
			goto L_EXIT;
		}
		break;
	}

L_EXIT:
	chdir("..");
	return e;
}

int main(string[] args) {
	
	// Command-line
	
	string outDir = "docs";
	string cacheDir = "cache";
	GetoptResult opt = void;
	try {
		opt = getopt(args,
		config.caseInsensitive,
		"d|outdir", "Output directory, defaults to 'docs'.", &outDir,
		"t|cachedir", "Cache directory, defaults to 'cache'.", &cacheDir,
		);
	} catch (Exception ex) {
		stderr.writeln(E_ERROR, ex.msg);
		return 1;
	}
	
	if (opt.helpWanted) {
		defaultGetoptPrinter(
			"D documentation updater\n"~
			"\n"~
			"Options",
			opt.options);
		return 0;
	}
	
	// Auto-select compiler (for single file operations)
	// And also validates that we have a compiler before proceeding
	
	if (system(DMD_VERSION) == 0) {
		detectedCompiler = Compiler.dmd;
		writeln(E_INFO~"Selected DMD as the default compiler");
		goto L_PATH;
	}
	if (system(LDC_VERSION) == 0) {
		detectedCompiler = Compiler.ldc;
		writeln(E_INFO~"Selected LDC as the default compiler");
		goto L_PATH;
	}
	if (system(GDC_VERSION) == 0) {
		detectedCompiler = Compiler.gdc;
		writeln(E_INFO~"Selected GDC as the default compiler");
		goto L_PATH;
	}
	stderr.writeln(E_ERROR~"Could not detect a D compiler");
	return 2;
	
	// Check tools if available
L_PATH:
	
	if (system(DUB_VERSION)) {
		stderr.writeln(E_ERROR~"dub missing from Path");
		return 3;
	}
	if (system(GIT_VERSION)) {
		stderr.writeln(E_ERROR~"git missing from Path");
		return 4;
	}
	
	// Preparations
	
	try {
		if (exists(outDir)) {
			if (isDir(outDir) == false) {
				stderr.writeln(E_ERROR~"output directory is a file");
				return 5;
			}
		} else {
			mkdir(outDir);
		}
		if (exists(cacheDir)) {
			if (isDir(cacheDir) == false) {
				stderr.writeln(E_ERROR~"cache directory is a file");
				return 5;
			}
		} else {
			mkdir(cacheDir);
		}
	} catch (Exception ex) {
		stderr.writeln(E_ERROR, ex.msg);
		return 6;
	}
	
	// Execution
	
	cacheDir = absolutePath(cacheDir);
	outDir = absolutePath(outDir);
	chdir(cacheDir);
	foreach (entry; entries) {
		writefln(E_INFO~"Processing entry '%s'", entry.name);
		int e = generateDoc(entry, cacheDir, outDir);
		if (e)
			stderr.writefln(E_ERROR~"Entry terminated with code %d", e);
	}
	
	return 0;
}
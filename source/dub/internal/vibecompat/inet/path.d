/**
	Contains routines for high level path handling.

	Copyright: © 2012 rejectedsoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module dub.internal.vibecompat.inet.path;

version (Have_vibe_d) public import vibe.inet.path;
else:

import std.algorithm;
import std.array;
import std.conv;
import std.exception;
import std.string;


/**
	Represents an absolute or relative file system path.

	This struct allows to do safe operations on paths, such as concatenation and sub paths. Checks
	are done to disallow invalid operations such as concatenating two absolute paths. It also
	validates path strings and allows for easy checking of malicious relative paths.
*/
struct Path {
	private {
		immutable(PathEntry)[] m_nodes;
		bool m_absolute = false;
		bool m_endsWithSlash = false;
	}
	
	/// Constructs a Path object by parsing a path string.
	this(string pathstr)
	{
		m_nodes = cast(immutable)splitPath(pathstr);
		m_absolute = (pathstr.startsWith("/") || m_nodes.length > 0 && (m_nodes[0].toString().countUntil(':')>0 || m_nodes[0] == "\\"));
		m_endsWithSlash = pathstr.endsWith("/");
		foreach( e; m_nodes ) assert(e.toString().length > 0);
	}
	
	/// Constructs a path object from a list of PathEntry objects.
	this(immutable(PathEntry)[] nodes, bool absolute)
	{
		m_nodes = nodes;
		m_absolute = absolute;
	}
	
	/// Constructs a relative path with one path entry.
	this(PathEntry entry){
		m_nodes = [entry];
		m_absolute = false;
	}
	
	/// Determines if the path is absolute.
	@property bool absolute() const { return m_absolute; }

	/// Resolves all '.' and '..' path entries as far as possible.
	void normalize()
	{
		immutable(PathEntry)[] newnodes;
		foreach( n; m_nodes ){
			switch(n.toString()){
				default:
					newnodes ~= n;
					break;
				case ".": break;
				case "..":
					enforce(!m_absolute || newnodes.length > 0, "Path goes below root node.");
					if( newnodes.length > 0 && newnodes[$-1] != ".." ) newnodes = newnodes[0 .. $-1];
					else newnodes ~= n;
					break;
			}
		}
		m_nodes = newnodes;
	}
	
	/// Converts the Path back to a string representation using slashes.
	string toString()
	const {
		if( m_nodes.empty ) return absolute ? "/" : "";
		
		Appender!string ret;
		
		// for absolute paths start with /
		version(Windows)
		{
			// Make sure windows path isn't "DRIVE:"
			if( absolute && !m_nodes[0].toString().endsWith(':') )
				ret.put('/');
		}
		else
		{
			if( absolute ) 
			{
				ret.put('/');
			}
		}
		
		foreach( i, f; m_nodes ){
			if( i > 0 ) ret.put('/');
			ret.put(f.toString());
		}

		if( m_nodes.length > 0 && m_endsWithSlash )
			ret.put('/');
		
		return ret.data;
	}
	
	/// Converts the Path object to a native path string (backslash as path separator on Windows).
	string toNativeString()
	const {
		if (m_nodes.empty) {
			version(Windows) {
				assert(!absolute, "Empty absolute path detected.");
				return m_endsWithSlash ? ".\\" : ".";
			} else return absolute ? "/" : m_endsWithSlash ? "./" : ".";
		}

		Appender!string ret;
		
		// for absolute unix paths start with /
		version(Posix) { if(absolute) ret.put('/'); }
		
		foreach( i, f; m_nodes ){
			version(Windows) { if( i > 0 ) ret.put('\\'); }
			version(Posix) { if( i > 0 ) ret.put('/'); }
			else { enforce("Unsupported OS"); }
			ret.put(f.toString());
		}
		
		if( m_nodes.length > 0 && m_endsWithSlash ){
			version(Windows) { ret.put('\\'); }
			version(Posix) { ret.put('/'); }
		}
		
		return ret.data;
	}
	
	/// Tests if `rhs` is an anchestor or the same as this path. 
	bool startsWith(const Path rhs) const {
		if( rhs.m_nodes.length > m_nodes.length ) return false;
		foreach( i; 0 .. rhs.m_nodes.length )
			if( m_nodes[i] != rhs.m_nodes[i] )
				return false;
		return true;
	}
	
	/// Computes the relative path from `parentPath` to this path.
	Path relativeTo(const Path parentPath) const {
		assert(this.absolute && parentPath.absolute);
		version(Windows){
			// a path such as ..\C:\windows is not valid, so force the path to stay absolute in this case
			if( this.absolute && !this.empty && m_nodes[0].toString().endsWith(":") &&
				!parentPath.startsWith(this[0 .. 1]) )
			{
				return this;
			}
		}
		int nup = 0;
		while( parentPath.length > nup && !startsWith(parentPath[0 .. parentPath.length-nup]) ){
			nup++;
		}
		Path ret = Path(null, false);
		ret.m_endsWithSlash = true;
		foreach( i; 0 .. nup ) ret ~= "..";
		ret ~= Path(m_nodes[parentPath.length-nup .. $], false);
		ret.m_endsWithSlash = this.m_endsWithSlash;
		return ret;
	}
	
	/// The last entry of the path
	@property ref immutable(PathEntry) head() const { enforce(m_nodes.length > 0); return m_nodes[$-1]; }

	/// The parent path
	@property Path parentPath() const { return this[0 .. length-1]; }

	/// The ist of path entries of which this path is composed
	@property immutable(PathEntry)[] nodes() const { return m_nodes; }

	/// The number of path entries of which this path is composed
	@property size_t length() const { return m_nodes.length; }

	/// True if the path contains no entries
	@property bool empty() const { return m_nodes.length == 0; }

	/// Determines if the path ends with a slash (i.e. is a directory)
	@property bool endsWithSlash() const { return m_endsWithSlash; }
	/// ditto
	@property void endsWithSlash(bool v) { m_endsWithSlash = v; }

	/// Determines if this path goes outside of its base path (i.e. begins with '..').
	@property bool external() const { return !m_absolute && m_nodes.length > 0 && m_nodes[0].m_name == ".."; }
		
	ref immutable(PathEntry) opIndex(size_t idx) const { return m_nodes[idx]; }
	Path opSlice(size_t start, size_t end) const {
		auto ret = Path(m_nodes[start .. end], start == 0 ? absolute : false);
		if( end == m_nodes.length ) ret.m_endsWithSlash = m_endsWithSlash;
		return ret;
	}
	size_t opDollar(int dim)() const if(dim == 0) { return m_nodes.length; }
	
	
	Path opBinary(string OP)(const Path rhs) const if( OP == "~" ) {
		Path ret;
		ret.m_nodes = m_nodes;
		ret.m_absolute = m_absolute;
		ret.m_endsWithSlash = rhs.m_endsWithSlash;
		ret.normalize(); // needed to avoid "."~".." become "" instead of ".."
		
		assert(!rhs.absolute, "Trying to append absolute path.");
		size_t idx = m_nodes.length;
		foreach(folder; rhs.m_nodes){
			switch(folder.toString()){
				default: ret.m_nodes = ret.m_nodes ~ folder; break;
				case ".": break;
				case "..":
					enforce(!ret.absolute || ret.m_nodes.length > 0, "Relative path goes below root node!");
					if( ret.m_nodes.length > 0 && ret.m_nodes[$-1].toString() != ".." )
						ret.m_nodes = ret.m_nodes[0 .. $-1];
					else ret.m_nodes = ret.m_nodes ~ folder;
					break;
			}
		}
		return ret;
	}
	
	Path opBinary(string OP)(string rhs) const if( OP == "~" ) { assert(rhs.length > 0, "Cannot append empty path string."); return opBinary!"~"(Path(rhs)); }
	Path opBinary(string OP)(PathEntry rhs) const if( OP == "~" ) { assert(rhs.toString().length > 0, "Cannot append empty path string."); return opBinary!"~"(Path(rhs)); }
	void opOpAssign(string OP)(string rhs) if( OP == "~" ) { assert(rhs.length > 0, "Cannot append empty path string."); opOpAssign!"~"(Path(rhs)); }
	void opOpAssign(string OP)(PathEntry rhs) if( OP == "~" ) { assert(rhs.toString().length > 0, "Cannot append empty path string."); opOpAssign!"~"(Path(rhs)); }
	void opOpAssign(string OP)(Path rhs) if( OP == "~" ) { auto p = this ~ rhs; m_nodes = p.m_nodes; m_endsWithSlash = rhs.m_endsWithSlash; }
	
	/// Tests two paths for equality using '=='.
	bool opEquals(ref const Path rhs) const {
		if( m_absolute != rhs.m_absolute ) return false;
		if( m_endsWithSlash != rhs.m_endsWithSlash ) return false;
		if( m_nodes.length != rhs.length ) return false;
		foreach( i; 0 .. m_nodes.length )
			if( m_nodes[i] != rhs.m_nodes[i] )
				return false;
		return true;
	}
	/// ditto
	bool opEquals(const Path other) const { return opEquals(other); }

	int opCmp(ref const Path rhs) const {
		if( m_absolute != rhs.m_absolute ) return cast(int)m_absolute - cast(int)rhs.m_absolute;
		foreach( i; 0 .. min(m_nodes.length, rhs.m_nodes.length) )
			if( m_nodes[i] != rhs.m_nodes[i] )
				return m_nodes[i].opCmp(rhs.m_nodes[i]);
		if( m_nodes.length > rhs.m_nodes.length ) return 1;
		if( m_nodes.length < rhs.m_nodes.length ) return -1;
		return 0;
	}

	hash_t toHash()
	const nothrow @trusted {
		hash_t ret;
		auto strhash = &typeid(string).getHash;
		try foreach (n; nodes) ret ^= strhash(&n.m_name);
		catch assert(false);
		if (m_absolute) ret ^= 0xfe3c1738;
		if (m_endsWithSlash) ret ^= 0x6aa4352d;
		return ret;
	}
}

struct PathEntry {
	private {
		string m_name;
	}
	
	this(string str)
	{
		assert(str.countUntil('/') < 0 && (str.countUntil('\\') < 0 || str.length == 1));
		m_name = str;
	}
	
	string toString() const { return m_name; }

	Path opBinary(string OP)(PathEntry rhs) const if( OP == "~" ) { return Path(cast(immutable)[this, rhs], false); }
	
	bool opEquals(ref const PathEntry rhs) const { return m_name == rhs.m_name; }
	bool opEquals(PathEntry rhs) const { return m_name == rhs.m_name; }
	bool opEquals(string rhs) const { return m_name == rhs; }
	int opCmp(ref const PathEntry rhs) const { return m_name.cmp(rhs.m_name); }
	int opCmp(string rhs) const { return m_name.cmp(rhs); }
}

private bool isValidFilename(string str)
{
	foreach( ch; str )
		if( ch == '/' || /*ch == ':' ||*/ ch == '\\' ) return false;
	return true;
}

/// Joins two path strings. subpath must be relative.
string joinPath(string basepath, string subpath)
{
	Path p1 = Path(basepath);
	Path p2 = Path(subpath);
	return (p1 ~ p2).toString();
}

/// Splits up a path string into its elements/folders
PathEntry[] splitPath(string path)
{
	if( path.startsWith("/") || path.startsWith("\\") ) path = path[1 .. $];
	if( path.empty ) return null;
	if( path.endsWith("/") || path.endsWith("\\") ) path = path[0 .. $-1];

	// count the number of path nodes
	size_t nelements = 0;
	foreach( i, char ch; path )
		if( ch == '\\' || ch == '/' )
			nelements++;
	nelements++;

	// reserve space for the elements
	auto elements = new PathEntry[nelements];
	size_t eidx = 0;

	// detect UNC path
	if(path.startsWith("\\"))
	{
		elements[eidx++] = PathEntry(path[0 .. 1]);
		path = path[1 .. $];
	}

	// read and return the elements
	size_t startidx = 0;
	foreach( i, char ch; path )
		if( ch == '\\' || ch == '/' ){
			enforce(i - startidx > 0, "Empty path entries not allowed.");
			elements[eidx++] = PathEntry(path[startidx .. i]);
			startidx = i+1;
		}
	elements[eidx++] = PathEntry(path[startidx .. $]);
	enforce(path.length - startidx > 0, "Empty path entries not allowed.");
	assert(eidx == nelements);
	return elements;
}

unittest
{
	Path p;
	assert(p.toNativeString() == ".");
	p.endsWithSlash = true;
	version(Windows) assert(p.toNativeString() == ".\\");
	else assert(p.toNativeString() == "./");

	p = Path("test/");
	version(Windows) assert(p.toNativeString() == "test\\");
	else assert(p.toNativeString() == "test/");
	p.endsWithSlash = false;
	assert(p.toNativeString() == "test");
}

unittest
{
	{
		auto unc = "\\\\server\\share\\path";
		auto uncp = Path(unc);
		version(Windows) assert(uncp.toNativeString() == unc);
		assert(uncp.absolute);
		assert(!uncp.endsWithSlash);
	}

	{
		auto abspath = "/test/path/";
		auto abspathp = Path(abspath);
		assert(abspathp.toString() == abspath);
		version(Windows) {} else assert(abspathp.toNativeString() == abspath);
		assert(abspathp.absolute);
		assert(abspathp.endsWithSlash);
		assert(abspathp.length == 2);
		assert(abspathp[0] == "test");
		assert(abspathp[1] == "path");
	}

	{
		auto relpath = "test/path/";
		auto relpathp = Path(relpath);
		assert(relpathp.toString() == relpath);
		version(Windows) assert(relpathp.toNativeString() == "test\\path\\");
		else assert(relpathp.toNativeString() == relpath);
		assert(!relpathp.absolute);
		assert(relpathp.endsWithSlash);
		assert(relpathp.length == 2);
		assert(relpathp[0] == "test");
		assert(relpathp[1] == "path");
	}

	{
		auto winpath = "C:\\windows\\test";
		auto winpathp = Path(winpath);
		assert(winpathp.toString() == "/C:/windows/test");
		version(Windows) assert(winpathp.toNativeString() == winpath);
		else assert(winpathp.toNativeString() == "/C:/windows/test");
		assert(winpathp.absolute);
		assert(!winpathp.endsWithSlash);
		assert(winpathp.length == 3);
		assert(winpathp[0] == "C:");
		assert(winpathp[1] == "windows");
		assert(winpathp[2] == "test");
	}

	{
		auto dotpath = "/test/../test2/././x/y";
		auto dotpathp = Path(dotpath);
		assert(dotpathp.toString() == "/test/../test2/././x/y");
		dotpathp.normalize();
		assert(dotpathp.toString() == "/test2/x/y");
	}

	{
		auto parentpath = "/path/to/parent";
		auto parentpathp = Path(parentpath);
		auto subpath = "/path/to/parent/sub/";
		auto subpathp = Path(subpath);
		auto subpath_rel = "sub/";
		assert(subpathp.relativeTo(parentpathp).toString() == subpath_rel);
		auto subfile = "/path/to/parent/child";
		auto subfilep = Path(subfile);
		auto subfile_rel = "child";
		assert(subfilep.relativeTo(parentpathp).toString() == subfile_rel);
  }
}

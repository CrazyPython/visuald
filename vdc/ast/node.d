// This file is part of Visual D
//
// Visual D integrates the D programming language into Visual Studio
// Copyright (c) 2010-2011 by Rainer Schuetze, All Rights Reserved
//
// License for redistribution is given by the Artistic License 2.0
// see file LICENSE for further details

module vdc.ast.node;

import vdc.util;
import vdc.semantic;
import vdc.lexer;
import vdc.ast.expr;
import vdc.ast.type;
import vdc.ast.mod;
import vdc.ast.tmpl;
import vdc.ast.decl;
import vdc.ast.misc;
import vdc.logger;
import vdc.interpret;

import std.exception;
import std.stdio;
import std.string;
import std.conv;
import std.algorithm;

class Node
{
	TokenId id;
	Attribute attr;
	Annotation annotation;
	TextSpan span; // file extracted from parent module
	
	Node parent;
	Node[] members;
	
	// semantic data
	int semanticSearches;
	Scope scop;
	
	this()
	{
		// default constructor needed for clone()
	}
	
	this(ref const(TextSpan) _span)
	{
		span = _span;
	}
	this(Token tok)
	{
		id = tok.id;
		span = tok.span;
	}
	this(TokenId _id, ref const(TextSpan) _span)
	{
		id = _id;
		span = _span;
	}

	mixin template ForwardCtor()
	{
		this()
		{
			// default constructor needed for clone()
		}
		this(ref const(TextSpan) _span)
		{
			super(_span);
		}
		this(Token tok)
		{
			super(tok);
		}
		this(TokenId _id, ref const(TextSpan) _span)
		{
			super(_id, _span);
		}
	}
		
	mixin template ForwardCtorTok()
	{
		this() {} // default constructor needed for clone()
		
		this(Token tok)
		{
			super(tok);
		}
	}
	
	mixin template ForwardCtorNoId()
	{
		this() {} // default constructor needed for clone()
		
		this(ref const(TextSpan) _span)
		{
			super(_span);
		}
		this(Token tok)
		{
			super(tok.span);
		}
	}
	
	void reinit()
	{
		id = 0;
		attr = 0;
		annotation = 0;
		members.length = 0;
		clearSpan();
	}

	Node clone()
	{
		Node	n = static_cast!Node(this.classinfo.create());
		
		n.id = id;
		n.attr = attr;
		n.annotation = annotation;
		n.span = span;
		
		foreach(m; members)
			n.addMember(m.clone());
		
		return n;
	}

	bool compare(const(Node) n) const
	{
		if(this.classinfo !is n.classinfo)
			return false;
		
		if(n.id != id || n.attr != attr || n.annotation != annotation)
			return false;
		// ignore span
		
		if(members.length != n.members.length)
			return false;
			
		for(int m = 0; m < members.length; m++)
			if(!members[m].compare(n.members[m]))
				return false;
	
		return true;
	}
	
	////////////////////////////////////////////////////////////
	abstract void toD(CodeWriter writer)
	{
		writer(this.classinfo.name);
		writer.nl();
		
		auto indent = CodeIndenter(writer);
		foreach(c; members)
			writer(c);
	}

	void toC(CodeWriter writer)
	{
		toD(writer);
	}

	////////////////////////////////////////////////////////////
	static string genCheckState(string state)
	{
		return "
			if(" ~ state ~ "!= 0)
				return;
			" ~ state ~ " = 1;
			scope(exit) " ~ state ~ " = 2;
		";
	}

	enum SemanticState
	{
		None,
		ExpandingNonScopeMembers,
		ExpandedNonScopeMembers,
		AddingSymbols,
		AddedSymbols,
		ResolvingSymbols,
		ResolvedSymbols,
	}
	int semanticState;
	
	void expandNonScopeSimple(Scope sc, int i, int j)
	{
		Node[1] narray;
		for(int m = i; m < j; )
		{
			Node n = members[m];
			narray[0] = n;
			Node[] nm = n.expandNonScopeBlock(sc, narray);
			if(nm.length == 1 && nm[0] == n)
			{
				n.addSymbols(sc);
				m++;
			}
			else
			{
				replaceMember(m, nm);
				j += nm.length - 1;
			}
		}
	}
	
	void expandNonScopeBlocks(Scope sc)
	{
		if(semanticState >= SemanticState.ExpandingNonScopeMembers)
			return;
		
		// simple expansions
		semanticState = SemanticState.ExpandingNonScopeMembers;
		expandNonScopeSimple(sc, 0, members.length);

		// expansions with interpretation
		Node[1] narray;
		for(int m = 0; m < members.length; )
		{
			Node n = members[m];
			narray[0] = n;
			Node[] nm = n.expandNonScopeInterpret(sc, narray);
			if(nm.length == 1 && nm[0] == n)
				m++;
			else
			{
				replaceMember(m, nm);
				expandNonScopeSimple(sc, m, m + nm.length);
			}
		}
		semanticState = SemanticState.ExpandedNonScopeMembers;
	}
	
	Node[] expandNonScopeBlock(Scope sc, Node[] athis)
	{
		return athis;
	}
	
	Node[] expandNonScopeInterpret(Scope sc, Node[] athis)
	{
		return athis;
	}
	
	void addMemberSymbols(Scope sc)
	{
		if(semanticState >= SemanticState.AddingSymbols)
			return;
		
		scop = sc;
		expandNonScopeBlocks(scop);

		semanticState = SemanticState.AddedSymbols;
	}
	
	void addSymbols(Scope sc)
	{
	}
	
	Scope enterScope(ref Scope nscope, Scope sc)
	{
		if(!nscope)
		{
			nscope = sc.pushClone();
			nscope.node = this;
			addMemberSymbols(nscope);
			return nscope;
		}
		return sc.push(nscope);
	}
	Scope enterScope(Scope sc)
	{
		return enterScope(scop, sc);
	}
	
	final void semantic(Scope sc)
	{
		assert(sc);
		
		logInfo("Scope(%s):semantic(%s=%s)", cast(void*)sc, this, cast(void*)this);
		LogIndent indent = LogIndent(1);
		
		_semantic(sc);
	}
	
	void _semantic(Scope sc)
	{
//		throw new SemanticException(text(this, ".semantic not implemented"));
		foreach(m; members)
			m.semantic(sc);
	}

	Scope getScope()
	{
		if(scop)
			return scop;
		if(parent)
			return parent.getScope();
		return null;
	}
	
	Type calcType()
	{
		return semanticErrorType(this, ".calcType not implemented");
	}

	Value interpret(Context sc)
	{
		return semanticErrorValue(this, ".interpret not implemented");
	}
	
	Value interpretCatch(Context sc)
	{
		try
		{
			return interpret(sc);
		}
		catch(InterpretException)
		{
		}
		return semanticErrorValue(this, ": interpretation stopped");
	}
	
	bool isTemplate()
	{
		return false;
	}
	Node expandTemplate(Scope sc, TemplateArgumentList args)
	{
		return this;
	}
	
	////////////////////////////////////////////////////////////
	invariant()
	{
		foreach(m; members)
			assert(m.parent is this);
	}
	
	void addMember(Node m) 
	{
		assert(m.parent is null);
		members ~= m;
		m.parent = this;
	}

	Node removeMember(int m) 
	{
		Node n = members[m];
		removeMember(m, 1);
		return n;
	}

	void removeMember(int m, int cnt) 
	{
		assert(m >= 0 && m + cnt <= members.length);
		for (int i = 0; i < cnt; i++)
			members[m + i].parent = null;
			
		for (int n = m + cnt; n < members.length; n++)
			members[n - cnt] = members[n];
		members.length = members.length - cnt;
	}
	
	Node[] removeAll() 
	{
		for (int m = 0; m < members.length; m++)
			members[m].parent = null;
		Node[] nm = members;
		members = members.init;
		return nm;
	}

	void replaceMember(Node m, Node[] nm) 
	{
		int n = std.algorithm.countUntil(members, m);
		assert(n >= 0);
		replaceMember(n, nm);
	}
	
	void replaceMember(int m, Node[] nm) 
	{
		if(m < members.length)
			members[m].parent = null;
		members = members[0..m] ~ nm ~ members[m+1..$];
		foreach(n; nm)
			n.parent = this;
	}
	
	T getMember(T = Node)(int idx) 
	{ 
		if (idx < 0 || idx >= members.length)
			return null;
		return static_cast!T(members[idx]);
	}

	Module getModule()
	{
		Node n = this;
		while(n)
		{
			if(n.scop)
				return n.scop.mod;
			n = n.parent;
		}
		return null;
	}
	string getModuleFilename()
	{
		Module mod = getModule();
		if(!mod)
			return null;
		return mod.filename;
	}
	
	ErrorValue semanticErrorValue(T...)(T args)
	{
		semanticErrorLoc(getModuleFilename(), span.start, args);
		return Singleton!(ErrorValue).get();
	}

	ErrorType semanticErrorType(T...)(T args)
	{
		semanticErrorLoc(getModuleFilename(), span.start, args);
		return Singleton!(ErrorType).get();
	}

	////////////////////////////////////////////////////////////
	void extendSpan(ref const(TextSpan) _span)
	{
		span.end.line = _span.end.line;
		span.end.index = _span.end.index;
	}
	void limitSpan(ref const(TextSpan) _span)
	{
		span.end.line = _span.end.line;
		span.end.index = _span.end.index;
	}
	void clearSpan()
	{
		span.end.line = span.start.line;
		span.end.index = span.start.index;
	}
}

interface CallableNode
{
	Value interpretCall(Context sc);
	
	ParameterList getParameterList();
	FunctionBody getFunctionBody();
}
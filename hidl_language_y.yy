%{
#include "hidl_language.h"
#include "hidl_language_y.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int yylex(yy::parser::semantic_type *, yy::parser::location_type *, void *);

#define lex_scanner ps->Scanner()

%}

%parse-param { Parser* ps }
%lex-param { void *lex_scanner }

%pure-parser
%skeleton "glr.cc"

%union {
    Element* element;
    std::vector<Element *> *elements;
    Field* field;
    Fields *fields;
    Type* type;
    int integer;
    bool boolean;
    std::string *str;
    std::vector<std::string *> *strings;
}

%token '(' ')' ',' '@' '=' '[' ']' '<' '>' '.' '{' '}' ';'
%token CONST STRUCT UNION ENUM TYPEDEF VERSION INTERFACE
%token PACKAGE GENERATES IMPORT REF VEC ON SELECTS
%token INT8 INT16 INT32 INT64 UINT8 UINT16 UINT32 UINT64
%token CHAR OPAQUE HANDLE STRINGTOK ONEWAY

%token<str> C_CHAR;
%token<element> IDENTIFIER
%token<element> COMMENT
%token<element> INTVALUE C_STR

%type<strings> namespace
%type<strings> annotations
%type<element> dotted_ids
%type<str> imports
%type<str> annotation_entry annotation  annotation_entries
%type<str> typedef_decl
%type<str> annotation_value annotation_values
%type<boolean> oneway
%type<element> scalar_value const_value
%type<elements> id_list namespace_list
%type<field> disc_union_field enum_field var_decl
%type<fields> enum_fields disc_union_fields var_decls_semi func_args
%type<type> union_type disc_union_type struct_type any_type one_word_type scalar_type
%type<token> error
%%

document
 : comments intro '{' decls '}' ';' comments {}

comments
 :
 | comments COMMENT { ps->AddComment($2); }

intro
 : version namespace imports INTERFACE IDENTIFIER
  { ps->SetInterface($5); }

version
 : VERSION INTVALUE '.' INTVALUE ';'
  { ps->SetVersion($2->GetIntegerValue(), $4->GetIntegerValue()); }

namespace
 : PACKAGE namespace_list ';'
  { ps->SetNamespace($2); }

imports
 : {}
 | imports import {}

import
 : IMPORT namespace_list ';'
  { ps->AddImport($2); }

namespace_list
 : IDENTIFIER
  { $$ = new std::vector<Element *>; $$->push_back($1); }
 | namespace_list '.' IDENTIFIER
  { $1->push_back($3); }

decls
 : comments
 | decls decl comments

decl
 : struct_decl    {}
 | enum_decl      {}
 | const_decl     {}
 | function_decl  {}
 | union_decl     {}
 | typedef_decl   {}

struct_decl
 : STRUCT IDENTIFIER '{' var_decls_semi '}' ';'
  { ps->AddStruct(new StructDecl($2, new StructType($4))); }

const_decl
 : CONST IDENTIFIER '=' const_value ';'
  { ps->AddConst(new Const($2, $4)); }

scalar_value
 : C_CHAR   {}
 | INTVALUE {}
 | IDENTIFIER   {}

const_value
 : scalar_value {}
 | C_STR        {}

enum_decl
 : ENUM IDENTIFIER ':' scalar_type '{' enum_fields '}' ';'
  { ps->AddEnum(new EnumDecl($2, new EnumType($4, $6))); }

function_decl
 : annotations oneway IDENTIFIER '(' func_args ')' ';'
  { ps->AddFunction(new Function($1, $2, $3, $5, nullptr)); }
 | annotations oneway IDENTIFIER '(' func_args ')' GENERATES '(' func_args ')' ';'
  { ps->AddFunction(new Function($1, $2, $3, $5, $9)); }


func_args
 :
  { $$ = new Fields; }
 | var_decl
  { $$ = new Fields; $$->Add($1); }
 | func_args ',' var_decl
  { $$->Add($3); }

var_decls_semi
 : var_decl ';'
  { $$ = new Fields; $$->Add($1); }
 | var_decls_semi var_decl ';'
  { $$->Add($2); }

var_decl
 : any_type IDENTIFIER
  { $$ = new Field($1, $2); }
 | any_type IDENTIFIER SELECTS '(' dotted_ids ')'
  { $$ = new Field($1, $2, $5); }

dotted_ids
 : IDENTIFIER {}
 | dotted_ids '.' IDENTIFIER
  { $1->AddDottedElement($3); }


union_decl
 : UNION IDENTIFIER '{' var_decls_semi '}' ';'
  { ps->AddUnion(new UnionDecl($2, new UnionType($4))); }
 | UNION IDENTIFIER ':' IDENTIFIER '{' disc_union_fields '}' ';'
  { ps->AddUnion(new UnionDecl($2, new UnionType(new NamedType($4), $6))); }

typedef_decl
 : TYPEDEF any_type IDENTIFIER ';'
  { ps->AddTypedef(new TypedefDecl($3, $2)); }

disc_union_fields
 : disc_union_field
  { $$ = new Fields; $$->Add($1); }
 | disc_union_fields disc_union_field
  { $1->Add($2); }

disc_union_field
 : any_type IDENTIFIER ON '(' id_list ')' ';'
  { $$ = new Field($1, $2, $5); }

id_list
 : IDENTIFIER
  { $$ = new std::vector<Element *>; $$->push_back($1); }
 | id_list ',' IDENTIFIER
  { $1->push_back($3); }

enum_fields
 : enum_field
  { $$ = new Fields; $$->Add($1); }
 | enum_fields ',' enum_field
  { $1->Add($3); }

enum_field
 : IDENTIFIER
  { $$ = new Field($1); }
 | IDENTIFIER '=' scalar_value
  { $$ = new Field($1, $3); }

annotations
 : {$$ = new std::vector<std::string *>;}
 | annotations annotation { $$->push_back($2); }

// TODO: Memory leaks here
annotation
 : '@' IDENTIFIER
  { $$ = new std::string($2->GetText()); }
 | '@' IDENTIFIER '(' const_value ')'
  { $$ = new std::string($2->GetText()); $$->append($4->GetText()); }
 | '@' IDENTIFIER '(' annotation_entries ')'
  { $$ = new std::string($2->GetText()); }

annotation_entries
 : annotation_entry
  {$$ = $1;}
 | annotation_entries ',' annotation_entry
  { $$->append(*$3); }

annotation_entry
 : IDENTIFIER '=' annotation_value
  { $$ = new std::string($1->GetText()); $$->append(" = "); $$->append(*$3); }
 | IDENTIFIER '=' '{' annotation_values '}'
  { $$ = new std::string($1->GetText()); $$->append(" = "); $$->append(*$4); }

annotation_values
 : annotation_value { }
 | annotation_values ',' annotation_value
  { $$ = $1; $$->append(*$3); }

annotation_value
 : const_value
  { $$ = new std::string($1->GetText()); }
 | annotation
  { $$ = new std::string(*$1); }

scalar_type
 : UINT8     { }
 | UINT16    { }
 | UINT32    { }
 | UINT64    { }
 | INT8      { }
 | INT16     { }
 | INT32     { }
 | INT64     { }
 | CHAR      { }
 | IDENTIFIER  { $$ = new NamedType($1); } // Check at runtime if this is really scalar

one_word_type
 : scalar_type
 | HANDLE    { }
 | STRINGTOK    { }
 | OPAQUE    { }

any_type
 : one_word_type {}
 | any_type '[' scalar_value ']'
  { $$=new ArrayType($1, $3); }
 | struct_type {}
 | union_type {}
 | disc_union_type {}
 | VEC '<' any_type '>'
  { $$=new VecType($3); }
 | REF '<' any_type '>'
  { $$=new RefType($3); }


struct_type
 : STRUCT '{' var_decls_semi '}'
  { $$=new StructType($3); }

union_type
 : UNION '{' var_decls_semi '}'
  { $$=new UnionType($3); }

disc_union_type
 : UNION ':' scalar_type '{' disc_union_fields '}'
  { $$=new UnionType($3, $5); }

oneway
 : { $$ = false;}
 | ONEWAY  { $$ = true;}

%%

#include <ctype.h>
#include <stdio.h>

void yy::parser::error(const yy::parser::location_type& l,
                       const std::string& errstr) {
  ps->Error(l.begin.line, "%s", errstr.c_str());
}
%{
/*
 * Copyright (c) 2002, 2004 Tama Communications Corporation
 *
 * This file is part of GNU GLOBAL.
 *
 * GNU GLOBAL is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2, or (at your option)
 * any later version.
 *
 * GNU GLOBAL is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.
 */

/*
 * scanner for C++ source code.
 */
#ifdef HAVE_CONFIG_H
#include <config.h>
#endif
#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include "global.h"
#include "anchor.h"
#include "incop.h"
#include "path2url.h"
#include "common.h"
#include "htags.h"
#include "../gctags/cpp_res.h"
#include "lexcommon.h"

#define LEXTEXT	cpptext
#define LEXLENG	cppleng

#ifdef ECHO
#undef ECHO
#endif
#define ECHO	echos(LEXTEXT)

#define YY_USER_ACTION DEFAULT_YY_USER_ACTION

%}
 /* Definitions */
H		0[Xx][0-9A-Fa-f]+
N		[0-9]+
L		{N}L?
D1		{N}\.{N}([Ee][+-]?{N})?
D2		\.{N}([Ee][+-]?{N})?
NUMBER		-?({L}|{D1}|{D2})
ALPHA		[a-zA-Z_\x80-\xff]
ALPHANUM	[a-zA-Z_\x80-\xff0-9]
WORD		{ALPHA}{ALPHANUM}*

%start	CPP C_COMMENT CPP_COMMENT SHELL_COMMENT STRING LITERAL
%option 8bit noyywrap stack prefix="cpp"
%%
 /* Comment */
<CPP>"/*"	{ echos(comment_begin); ECHO; yy_push_state(C_COMMENT); }
<C_COMMENT>"*/"	{ ECHO; echos(comment_end); yy_pop_state(); }
<C_COMMENT>.	{ put_char(LEXTEXT[0]); }
<CPP>"//"	{ echos(comment_begin); ECHO; yy_push_state(CPP_COMMENT); }

 /* String */
<CPP>\"		{ ECHO; yy_push_state(STRING); }
<STRING>\"	{ ECHO; yy_pop_state(); }
<STRING>\\.	{ put_char(LEXTEXT[0]); put_char(LEXTEXT[1]); }

 /* Literal */
<CPP>\'		{ ECHO; yy_push_state(LITERAL); }
<LITERAL>\'	{ ECHO; yy_pop_state(); }
<LITERAL>\\.	{ put_char(LEXTEXT[0]); put_char(LEXTEXT[1]); }

<CPP>^[ \t]*\#[ \t]*include {
		int c;

		put_macro(LEXTEXT);
		/*
		 * #include|   <aaa/bbb.h>|
		 *         ~~~~~~~~~~~~~~~~
		 */
		while ((c = input()) && c != '\n' && isspace(c))
			echoc(c);
		if (c == '\n') {
			unput(c);
		} else if (c) {
			char path[MAXPATHLEN+1], *p = path;
			struct data *inc;
			int sep = 0;

			if (c == '"') {
				sep = c;
				echoc(c);
			} else if (c == '<') {
				sep = '>';
				echos(quote_little);
			}
			/* pick up path name */
			while ((c = input()) && c != sep && c != '\n')
				*p++ = c;
			*p = '\0';
			if (c == sep) {
				char *basename = locatestring(path, "/", MATCH_LAST);

				if (basename)
					basename++;
				else
					basename = path;
				inc = get_inc(basename);
				if (inc) {
					echos("<A HREF=");
					if (inc->count == 1)
						echos(path2url(strbuf_value(inc->contents)));
					else
						echo("../%s/%d.%s", INCS, inc->id, HTML);
					echoc('>');
				}
				echos(path);
				if (inc)
					echos("</A>");
				if (sep == '>')
					echos(quote_great);
				else
					echoc(sep);
			} else {
				echos(path);
				if (c == '\n')
					unput(c);
			}
		}
	}
<CPP>^[ \t]*\#[ \t]*{WORD} {
		int i = 0;
		char *p;

		p = locatestring(LEXTEXT, " ", MATCH_LAST);

		if (!p) {
			p = LEXTEXT;
			i = LEXLENG;
		} else {
			static char buf[IDENTLEN];

			p++;
			if (*p == '#')
				p++;
			buf[i++] = '#';
			while (*p) {
				buf[i++] = *p++;
				if (i >= sizeof(buf))
					die("Too long name '%s'.", LEXTEXT);
			}
			buf[i] = '\0';
			p = buf;
		}
		if (i > 0 && reserved_sharp(p, i))
			put_macro(LEXTEXT);
		else
			echos(LEXTEXT);
	}
<CPP>{NUMBER}	ECHO;
<CPP>{WORD} {
		if (reserved_word(LEXTEXT, LEXLENG))
			put_reserved_word(LEXTEXT);
		else {
			struct anchor *a = anchor_get(LEXTEXT, LEXLENG, 0, LINENO);
			if (a) {
				put_anchor(gettag(a), a->type, LINENO);
				a->done = 1;
			} else {
				ECHO;
			}
		}
	}
<CPP>[{}]	{ put_brace(LEXTEXT); }
 /* New line */
\n		DEFAULT_END_OF_LINE_ACTION
.		{ put_char(LEXTEXT[0]); }

%%
void
cpp_parser_init(ip)
	FILE *ip;
{
	DEFAULT_BEGIN_OF_FILE_ACTION
	BEGIN CPP;
}
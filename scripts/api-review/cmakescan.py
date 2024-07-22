#!/usr/bin/env python3
# Usage: see api-review-gen
# Copyright (C) 2023 The Qt Company Ltd.
# SPDX-License-Identifier: LicenseRef-Qt-Commercial OR LGPL-3.0-only OR GPL-2.0-only OR GPL-3.0-only
"""Script to scan a CMakeLists.txt file for a list of public API-defining headers.

A somewhat brutal recursive-descent parser for as much (and a random
bit more) of the file format as matters to the task in hand. Assumes
the source is well-enough formed. See its main()'s documentation for
details.
"""
import re
from pathlib import Path

class ParseError(Exception): pass
class StreamPosition(object):
    def __init__(self):
        self.line = self.column = 0
    def __repr__(self):
        return f'line: {self.line}, column: {self.column}'
    def consume(self, text):
        endl = text.rfind('\n')
        if endl < 0:
            self.column += len(text)
        else:
            self.column = len(text) - endl - 1
            self.line += text.count('\n')

        return text

class CMakeScanner(object):
    def __init__(self, module, root):
        """Set up a scanner for the named module.

        First argument, the module name, is used to select which
        function-calls are of interest. It is saved as self.module for
        future reference. Second argument, root, is the path to the
        directory in which the CMakeLists.txt file being parsed was
        found: this should be given relative to the git module's
        root. Paths of headers in the source-file lists are given
        relative to the CMakeLists.txt file, so this root path is
        prepended to each to make them relative to the git module's
        root."""
        self.module, self.root = module, root
    # Parsing is structured in various layers, as class methods.
    #
    # There's a stack of __*ing() methods reaching down from the top layer,
    # that forward the raw stream and its position tracker to __tokenize,
    # calling their respective layers' sub-layer processors, __*ed(), on the
    # stream of tokens they get back from the layer below, to produce the
    # stream they deliver to the layer above. The __*ed() call spots the starts
    # of the structures it's there to recognize and delegates to the plain
    # verb-named __* function, passing it a list of the opening token(s) of the
    # structure, to which it'll append the rest of the structure before
    # packaging the sequence of tokens as an object of a structure-appropriate
    # sub-type of TokenSeq, which it returns. Its collecting of tokens to
    # package in this way may well recurse into itself, if it spots the opening
    # of an inner instance of its structure type (or another recognized at the
    # same layer of the parser).  The structures we need to recognize are
    # simple enough that this suffices.

    class Token(object):
        def __init__(self, text):
            self.text = text
        def __bool__(self):
            return self.text
        def __eq__(self, text):
            return self.text == text

        def __str__(self):
            return f'{self.__class__.__name__}("{self.text}")'
        __repr__ = __str__

    # Sub-classes are used to package distinct types of Token.
    class Gap(Token): pass
    class Word(Token): pass
    class KeyWord(Word): pass
    class String(Token):
        @property
        def contents(self): # Only used for private filter regexes.
            # Should this unescape ?
            return self.text[1:-1]

    # Throw-away tool function, to tunnel into __tokenize() and delete later:
    # a pseudo-constructor for Word and KeyWord that choses which to use.
    def word(text, W=Word, K=KeyWord):
        if text in ('if', 'elseif', 'else', 'endif',
                    'foreach', 'endforeach',
                    'function', 'endfunction',
                    'macro', 'endmacro',
                    'set'):
            return K(text)
        return W(text)
    @staticmethod
    def __tokenize(stream, position, G=Gap, S=String, W=word):
        """Digests the stream into basic lexical tokens.

        First parameter, stream, must be an iterable over lines of text. These
        are tacitly ''.join()ed but only as fast as what's been scanned has
        been consumed enough to make it necessary to read the next. Second
        parameter, position, should be a StreamPosition object, whose consume()
        will be passed all characters as they are consumed by the tokenizer, so
        that it can keep track of the line and column number of the most
        recently digested character of the input. See __controlling() for how
        that information can propagate to error messages.

        Prunes out comments, combining any space before and after. Yields
        successive fragments of text as either (quoted) String, Word, KeyWord
        or Gap (spacing) objects or single characters.

        For these purposes, numbers are words. File paths and command-line
        parameters will be broken up at their punctuators; see __glued() for
        how those get stitched back together again, possibly with variable
        references within them expanded in the process. No attempt is made to
        parse quoted strings for variable references, even though CMake does
        support that; the parameter blocks we need don't seem to exercise that
        feature."""
        def alnumunder(ch):
            return ch.isalnum() or ch == '_'
        def gather(text, test):
            assert text and test(text[0])
            end = 1
            while end < len(text) and test(text[end]):
                end += 1
            return end

        text = space = ''
        for line in stream:
            assert not text or text.endswith('\n')
            text = text + line
            while text:
                tail = text.lstrip()
                gap = text[:-len(tail)] if tail else text
                if gap:
                    space += position.consume(gap)
                    text = tail
                    if not text:
                        break

                if text.startswith('"'):
                    try:
                        end = text.index('"', 1)
                        assert end > 0, "Expected ValueError on no match"
                        while text[end - 1] == '\\':
                            count = 1
                            while text[end - count - 1] == '\\':
                                count += 1
                            if count % 2 == 0:
                                break # This double-quote wasn't escaped
                            end = text.index('"', end + 1)
                    except ValueError:
                        break # out of the while loop; need to consume more.
                    yield S(position.consume(text[:end + 1]))
                    # We discard spacing around String tokens already.
                    text = text[end + 1:]
                    tail = text.lstrip()
                    position.consume(text[:-len(tail)])
                    text, space = tail, ''
                elif text.startswith('#'):
                    try:
                        end = text.index('\n')
                    except ValueError:
                        position.consume(text)
                        text = ''
                    else:
                        position.consume(text[:end])
                        text = text[end:]
                else:
                    if space:
                        # Spacing still matters around words and ${...} expressions.
                        yield G(space)
                        space = ''

                    if alnumunder(text[0]):
                        end = gather(text, alnumunder)
                        yield W(position.consume(text[:end]))
                        text = text[end:]
                    elif text.startswith(':'):
                        end = gather(text, lambda ch: ch == ':')
                        yield position.consume(text[:end])
                        text = text[end:]
                    else:
                        yield position.consume(text[0])
                        text = text[1:]
            # Empty or incomplete text; consume next line.
        # End stream.
        # If we have dangling space, ignore it; but not non-space.
        # We might have an unterminated quoted string.
        if text:
            raise ParseError("Dangling text at end of stream", text)
    del word

    class TokenSeq(object):
        """A sequence of objects and maybe some raw strings.

        At the lowest layer of parsing only Token objects appear, but higher
        layer constructs may include TokenSeq objects."""
        def __init__(self, *tokens):
            self.tokens = tokens
            assert self._well_formed(), tokens

        # For derived classes to over-ride:
        _joiner_ = ' '
        def _well_formed(self):
            return True

        # ... to configure constructor assertion and:
        @property
        def text(self):
            return self._joiner_.join(tok if isinstance(tok, str) else tok.text
                                      for tok in self.tokens)

        def __eq__(self, other):
            if not isinstance(other, str):
                other = other.text
            return self.text == other

        # In pratice, both callers pass Function as cls.
        def traverse(self, cls, test):
            """Iterates self's children and theirs.

            Yields those that are instances of cls for which test returns
            true. For children that are themselves TokenSeq, recurses into them
            rather than yielding them. Yields self, when relevant, after all
            relevant children of self."""
            for tok in self.tokens:
                try:
                    inner = tok.traverse
                except AttributeError:
                    if isinstance(tok, cls) and test(tok):
                        yield tok
                else:
                    yield from inner(cls, test)

            if isinstance(self, cls) and test(self):
                yield self

    # Evaluate layer
    #
    # Identifying ${...} and $<...> tokens for later substitution.
    #
    # This should also be applied to String contents, in principle.
    # However, no such tokens are seen in SOURCES blocks, for now at least.

    class Evaluate (TokenSeq):
        """Object representing a CMake variable reference.

        Used to package a ${...} or $<...> expression, for eventual
        evaluation."""
        _joiner_ = ''
        def _well_formed(self):
            return (len(self.tokens) >= 4 and self.tokens[0] == '$'
                    and (self.tokens[1], self.tokens[-1]) in (('{', '}'), ('<', '>')))
        @property
        def variable(self):
            return self.tokens[2]
        @property
        def default(self):
            if len(self.tokens) > 5 and self.tokens[3] == ':':
                return self.tokens[4]

    __vareval = {'{': '}', '<': '>'}
    @classmethod
    def __expand(cls, toks, tokenstream, E=Evaluate, S=Gap):
        """Parse a ${...} or $<...> token, after its opening.

        Caller has spotted the opening tokens and saved them in toks; this now
        finds the rest, potentially recursing into other tokens of the same
        form, and packages the result as an Evaluate object."""
        assert len(toks) > 1 and toks[0] == '$'
        closer = cls.__vareval[toks[1]]
        try: # We need one token of look-ahead
            last = next(tokenstream)
            while isinstance(last, S):
                last = next(tokenstream)
        except StopIteration:
            pass
        else:
            if last == closer:
                toks.append(last)
                return E(*toks)

            for tok in tokenstream:
                if isinstance(tok, S):
                    continue
                if tok == closer:
                    toks.append(last)
                    toks.append(tok)
                    return E(*toks)
                if last == '$' and isinstance(tok, str) and tok in cls.__vareval:
                    last = cls.__expand([last, tok], tokenstream)
                    continue
                toks.append(last)
                last = tok
            # Fell off end; include last in error message.
            toks.append(last)

        raise ParseError("Unclosed $-evaluator", closer, toks)

    @classmethod
    def __expanded(cls, tokenstream):
        """Identifies ${...} and $<...> constructs in the token stream.

        Forwards tokens not involved in those unchanged, packages those that
        make up these constructs into Evaluate objects."""
        try: # We need one token of look-ahead:
            last = next(tokenstream)
        except StopIteration:
            pass
        else:
            for tok in tokenstream:
                if not isinstance(last, str) or last != '$':
                    pass # Even if we do have < or {, it's just another token.
                elif isinstance(tok, str) and tok in cls.__vareval:
                    last = cls.__expand([last, tok], tokenstream)
                    continue

                yield last
                last = tok
            yield last

    # Glue layer
    #
    # Gluing together "words" and common separators with no spacing between
    # them, for example to build file-names out of path fragments. Spacing
    # ceases being significant after this step, so is discarded.

    class Glue(TokenSeq):
        _joiner_ = ''
        def _well_formed(self):
            return len(self.tokens) > 1
    @classmethod
    def __glued(cls, tokenstream, G=Glue, W=(Word, Evaluate), S=Gap):
        """Combine word fragments, discard spacing.

        As long as there is no spacing between the word fragments, we presume
        they are juxtaposed. Evaluations of ${...} and $<...> count as word
        fragments, as do alphanumeric and underscore sequences, along with the
        various punctuators common in file-names, command-line options and
        CMake package names. Each sequence of juxtaposed tokens to be
        recombined is packaged in a Glue object that replaces those
        tokens.

        Tokens not caught up in such sequences are simply forwarded as part of
        the resulting token stream, with the exception of Gap (spacing) tokens,
        as we have no further interest in these."""
        def glued(ts, Glue=G):
            return Glue(*ts) if len(ts) > 1 else ts[0]
        toks = [] # Potentially many tokens of look-ahead
        for tok in cls.__expanded(tokenstream):
            # The : is doubled, so we recognize '::' as a token.
            if tok in './-,::' if isinstance(tok, str) else isinstance(tok, W):
                toks.append(tok)
                continue
            if toks:
                yield glued(toks)
                toks.clear()
            if not isinstance(tok, S):
                yield tok
        if toks:
            yield glued(toks)

    @classmethod
    def __gluing(cls, stream, position):
        """Parses raw-level tokens to concatenate certain fragments.

        Recognizes ${...} and $<...> tokens and glues together, where there are
        no spacs between them, runs of these, plain words (including keywords)
        and punctuators that tend to show up in CMake identifiers, paths and
        command-line options. Once it has done this, spacing tokens are no
        longer relevant, so it discards them."""
        yield from cls.__glued(cls.__tokenize(stream, position))

    # Call layer
    #
    # Handling of functions, their parameter lists and the grouping of those
    # parameters by capitalized words - in two sub-layers.

    # Nest sub-layer
    #
    # Handling of (potentially nested) parenthesised sub-sequences of tokens:
    class Nest(TokenSeq):
        def _well_formed(self):
            return self.tokens[0] == '(' and self.tokens[-1] == ')'
        @classmethod
        def __rescan(cls, toks, joiner):
            toks = (toks[0],) + tuple(joiner(iter(toks[1:-1]))) + (toks[-1],)
            return cls(*toks)
        def rescan(self, joiner):
            return self.__rescan(self.tokens, joiner)

    @classmethod
    def __nest(cls, toks, tokenstream, N=Nest):
        """Parses a parenthesised sequence of tokens.

        Caller has found an open-parenthesis and stored it in toks, to which
        this function appends further tokens up to the matching close,
        replacing any inner parenthesised sequences in between by calling
        itself recursively, and packages the result in a Nest object."""
        for tok in tokenstream:
            if tok == ')':
                toks.append(tok)
                return N(*toks)

            if tok == '(':
                toks.append(cls.__nest([tok], tokenstream))
            else:
                toks.append(tok)
        raise ParseError("Unclosed parentheses", toks)

    @classmethod
    def __nested(cls, tokenstream):
        """Recognize parentheses and match opens up with closes.

        Propagates tokens not between parentheses unchanged, replaces each
        parenthesised sequence of tokens with a Nest object. Raises ParseError
        if it finds any unmatched parentheses."""
        for tok in tokenstream:
            if tok == ')':
                raise ParseError("Unopened parentheses", tok)

            if tok == '(':
                yield cls.__nest([tok], tokenstream)
            else:
                yield tok

    @classmethod
    def __nesting(cls, stream, position):
        """Parses glue-level tokens to match parentheses.

        Groups each matched pair of parentheses, plus everything between them,
        into a Nest; supports recursive nesting of inner parentheses, to
        arbitrary depth (albeit I've seen no examples of that in CMakeLists.txt
        files)."""
        yield from cls.__nested(cls.__gluing(stream, position))

    # Function / Param sub-layer
    #
    # Handling of function calls and grouping of their parameters into blocks
    @staticmethod
    def __is_param_name(tok, W=Word, K=KeyWord):
        """Recognizer for parameter names in parameter lists.

        Only upper-case Words that aren't KeyWords are considered; and some
        names are excluded because they appear in the values of other
        parameters."""
        return (isinstance(tok, W) and not isinstance(tok, K)
                and tok.text.isupper()
                # Various DEFINES are upper-case, starting with QT,
                # and POLICIES have a QTP prefix.
                and not ((tok.text.startswith('QT')
                          and tok.text != 'QT_LICENSE_ID')
                         or tok.text.startswith('TEST_')))

    class Param(TokenSeq):
        """A single parameter block.

        Starts with a word for which __is_param_name() is true, followed by
        assorted things for which it isn't. Far from a complete solution in
        general, but we only care about source-file groups and the private
        header filter groups, for which it suffices. Has properties:

          name -- the first token
          value -- all the remaining tokens
          is_source -- true for source lists
          is_private_filter -- is name PRIVATE_HEADER_FILTERS ?

        The recognized source lists are SOURCES and NO_*_SOURCES.

        Although headers matching {RHI,QPA}_HEADER_FILTERS are not subject to
        strict compatibility commitments, they are considered semi-public API,
        hence reviewed so that - at least - we're aware of and do discuss any
        incompatible changes to them. So these are not filtered out here."""
        @property
        def name(self):
            return self.tokens[0]
        @property
        def value(self):
            return self.tokens[1:]

        @property
        def is_source(self):
            if self.name == 'SOURCES':
                return True
            name = self.name if isinstance(self.name, str) else self.name.text
            return name.startswith('NO_') and name.endswith('_SOURCES')
        @property
        def is_private_filter(self):
            return self.name == 'PRIVATE_HEADER_FILTERS'

        def headers(self, lookup, *exclude):
            """Iterate the public headers named in this parameter block.

            First argument is a callable to which to pass each token, that will
            iterate over possible values for that token. See __evaluate().

            Optional further arguments are callables which take a string
            (presumed to be a file name) and return true if it should be
            excluded; for example, matchers for regexes named in a
            PRIVATE_HEADER_FILTERS parameter (e.g. ".*\\.qpb\\.h" for
            protobuf).

            Only names ending with .h are considered and those ending in _p.h
            or that have a 3rdparty path component are already filtered out, as
            are any starting with a ../ path component. The intent is to mirror
            what syncqt does to generate the public include/ directory."""
            if self.is_source:
                for tok in self.value:
                    for name in lookup(tok):
                        if not name.endswith('.h') or name.endswith('_p.h'):
                            continue
                        if name.startswith('3rdparty/') or '/3rdparty/' in name:
                            continue
                        if name.startswith('../'):
                            continue
                        if any(e(name) for e in exclude):
                            continue
                        yield name

    @classmethod
    def __split_params(cls, tokenstream, P=Param):
        """Break up a parameter list into blocks.

        Each token for which __is_param_name() is true starts a block, which is
        packaged as a Param object if it has any further tokens in it, This
        ensures that the SOURCES (and similar variables) are easy to pick out
        from parameter lists."""
        def grouped(ps, Param=P):
            return Param(*ps) if len(ps) > 1 else ps[0]
        isName, params = cls.__is_param_name, []
        for tok in tokenstream:
            if isName(tok):
                if params:
                    yield grouped(params)
                    params.clear()
                params.append(tok)
            elif params:
                params.append(tok)
            else:
                yield tok
        if params:
            yield grouped(params)

    class Function(TokenSeq):
        """A function call.

        This comprises a function name (which may be a keyword) and a Nest
        representing its parameter list; these can be accessed by properties
        .function and .parameters; the latter omits the parentheses round the
        parameter list."""
        def _well_formed(self):
            # tokens[0] is a Word or Glue, tokens[1] is a Nest.
            if len(self.tokens) == 2:
                ps = self.tokens[1].tokens
                return ps[0] == '(' and ps[-1] == ')'
            return False
        @property
        def function(self):
            return self.tokens[0].text
        @property
        def parameters(self):
            return self.tokens[1].tokens[1:-1]

        @staticmethod
        def __adds_module(func):
            return func.startswith('qt_internal_add_') and func.endswith('_module')
        def grows_module(self, module):
            """True if this function contributes to the contents of the named module.

            This basically tests whether module is self.parameters[0] and
            self.function is either qt_internal_extend_target(module ...) or
            qt_internal_add*_module(module ...)."""
            func = self.function
            if self.__adds_module(func) or func == 'qt_internal_extend_target':
                mod = self.parameters[0]
                return not isinstance(mod, str) and mod.text == module
            return False

    @classmethod
    def __called(cls, tokenstream, F=Function, N=Nest, W=(Word, Glue), K=KeyWord):
        """Recognize function calls and turn them into Function objects.

        Assumes there are no function calls within the parameter list of the
        function calls. Recognizes any word (including keyword) followed by a
        parenthesized token sequence, with or without space between the word
        (function name) and open-parenthesis (of the parameter list). If the
        function isn't a keyword, the parameter list gets rescanned to
        decompose it into blocks starting with upper-case names, such as
        SOURCES; see __split_params() and Nest.rescan()."""
        try: # We need one token of look-ahead.
            last = next(tokenstream)
        except StopIteration:
            pass
        else:
            for tok in tokenstream:
                if isinstance(tok, N) and isinstance(last, W):
                    if not isinstance(last, K):
                        tok = tok.rescan(cls.__split_params)
                    last = F(last, tok)
                    continue
                yield last
                last = tok
            yield last

    # Control structure layer
    #
    # Handling of if/elseif/else/endif and foreach/endforeach blocks.
    #
    # Assumption: no conditionals appear *inside* parameter lists.
    # Conditional inclusion in a SOURCES list is handled by
    # conditional calls to functions to extend the list.

    class Conditional(TokenSeq):
        def _well_formed(self):
            return (self.tokens[0].function == 'if'
                    and self.tokens[-1].function == 'endif')
    @classmethod
    def __conditional(cls, tokenstream, toks, seenelse=False,
                      C=Conditional, F=Function, K=KeyWord):
        """Recognize if() blocks and turn them into Conditional objects.

        This may, of course, involve recursively parsing inner conditionals and
        loops."""
        for tok in tokenstream:
            if isinstance(tok, F) and isinstance(tok.tokens[0], K):
                if tok.function == 'if':
                    toks.append(cls.__conditional(tokenstream, [tok]))
                    continue
                if tok.function == 'endif':
                    toks.append(tok)
                    return C(*toks)
                if tok.function == 'foreach':
                    toks.append(cls.__foreach(tokenstream, [tok]))
                    continue
                if seenelse and tok.function in ('elseif', 'else'):
                    raise ParseError("Not allowed after else()", tok, toks)
                if tok.function == 'elseif':
                    toks.append(tok)
                    return cls.__conditional(tokenstream, toks)
                if tok.function == 'else':
                    toks.append(tok)
                    return cls.__conditional(tokenstream, toks, True)
                if tok.function == 'endforeach':
                    raise ParseError("Unstarted loop", tok, toks)
            toks.append(tok)
        if toks:
            raise ParseError("Unterminated conditional", toks)

    class ForEach(TokenSeq):
        def _well_formed(self):
            return (self.tokens[0].function == 'foreach'
                    and self.tokens[-1].function == 'endforeach')
    @classmethod
    def __foreach(cls, tokenstream, toks, E=ForEach, F=Function, K=KeyWord):
        """Recognize foreach() blocks and turn them into ForEach objects.

        This may, of course, involve recursively parsing inner loops and
        conditional blocks."""
        for tok in tokenstream:
            if isinstance(tok, F) and isinstance(tok.tokens[0], K):
                if tok.function == 'foreach':
                    toks.append(cls.__foreach(tokenstream, [tok]))
                    continue
                if tok.function == 'endforeach':
                    toks.append(tok)
                    return E(*toks)
                if tok.function == 'if':
                    toks.append(cls.__conditional(tokenstream, [tok]))
                    continue
                if tok.function in ('elseif', 'else', 'endif'):
                    raise ParseError("Unstarted conditional fragment", tok, toks)
            toks.append(tok)

    @classmethod
    def __controlled(cls, tokenstream, F=Function, K=KeyWord):
        """Recognize control structures, recursively.

        Represents them as Conditional and ForEach objects. These may be
        arbitrarily nested. Raises ParseError on mismatched control
        structure."""
        for tok in tokenstream:
            if isinstance(tok, F) and isinstance(tok.tokens[0], K):
                if tok.function == 'if':
                    yield cls.__conditional(tokenstream, [tok])
                    continue
                if tok.function == 'foreach':
                    yield cls.__foreach(tokenstream, [tok])
                    continue
                if tok.function in ('elseif', 'else', 'endif'):
                    raise ParseError("Unstarted conditional fragment", tok)
                if tok.function == 'endforeach':
                    raise ParseError("Unstarted loop", tok)
            yield tok

    @classmethod
    def __controlling(cls, stream):
        """Parses nesting-level tokens to identify control constructs.

        Recognizes function calls and (as grouped special cases of those)
        if/else/elsif/endif chains and foreach/endforeach blocks,
        recursively. Turns a nesting-level token stream into the top level
        token stream. Collaborates with __tokenize() to keep track of position
        in the input stream and adds a description of it to the end of the
        .args of any Exception triggered during parsing."""
        position = StreamPosition()
        try:
            yield from cls.__controlled(cls.__called(cls.__nesting(stream, position)))
        except Exception as what:
            what.args += (repr(position),)
            raise

    # End of parsing (all done by class methods).

    # Actual evaluation of Evaluate nodes and actual gluing of Glue
    # nodes, including lookup of variables set:
    def __single_value(self, token):
        """Converts a variable name to the variable's single value.

        If the variable was not set, token.text is returned instead; if the
        variable was set to more than one word, ParseError is raised."""
        seq = iter(self.__evaluate(token))
        try:
            result = next(seq)
        except StopIteration:
            # Represent the expansion of an unset variable by its raw text
            return token.text
        for extra in seq:
            raise ParseError("Glued variable has multi-candidate value", token, result, extra)
        return result

    def __evaluate(self, tok, E=Evaluate, G=Glue, T=TokenSeq):
        """Convert a token to its final textual representation."""
        if isinstance(tok, E):
            # We're not interested in generated files, in the build tree:
            if not '_BUILD_' in tok.variable.text:
                yield from self.__lookup(tok.variable, tok.default)
        elif isinstance(tok, G):
            yield ''.join(self.__single_value(t) for t in tok.tokens)
        elif isinstance(tok, T):
            for kid in tok.tokens:
                yield from self.__evaluate(kid)
        else:
            yield tok if isinstance(tok, str) else tok.text

    def __lookup(self, variable, default=None, F=Function):
        """Yields every non-empty word of the expanded variable.

        First parameter, variable, is the variable name to look up. Optional
        second, default, is the value to use if it has never been set. If the
        variable has been set several times, for example in different branches
        of a conditional, all values to which it has been set are yielded.

        This may, of course, involve recursively expanding any other variables
        used within the value of the variable. Assumes such recursion never
        needs to expand the same variable within its own expansion."""
        for tok in self.tokens:
            for kid in tok.traverse(F, lambda k: k.function == 'set'):
                ps = kid.parameters
                if ps[0] == variable:
                    for tok in ps[1:]:
                        for val in self.__evaluate(tok):
                            if val:
                                yield val
                                default = None
        if default is not None:
            yield from self.__evaluate(default)

    # Traverse parameter blocks of interest:
    def __modparam(self, test, F=Function, P=Param):
        """Iterates parameter blocks that meet a given condition.

        Calls its single parameter, test, on each Param block of each Function,
        found during a traverse() of each token in self.tokens, that defines or
        extends our module as a target; yields those for which test() returns
        true."""
        for tok in self.tokens:
            for kid in tok.traverse(F, lambda k: k.grows_module(self.module)):
                for param in kid.parameters:
                    if isinstance(param, P) and test(param):
                        yield param

    @property
    def __private_filters(self, S=String):
        """Iterator over private header regular expressions.

        Specifically, those found in PRIVATE_HEADER_FILTERS blocks of function
        calls that define or extend our module."""
        for param in self.__modparam(lambda p: p.is_private_filter):
            for tok in param.value:
                if isinstance(tok, str):
                    yield tok
                elif isinstance(tok, S):
                    yield tok.contents
                else:
                    raise ParseError(
                        "Neither regex nor string as private header filter",
                        tok, param.value)

    # Public API:
    def ingest(self, stream):
        """Parse stream, save result in self.tokens

        After this, self.headers will be able to report the interesting part of
        what it read."""
        self.tokens = tuple(self.__controlling(stream))

    @property
    def headers(self):
        """Iterates the public headers of self.module

        Won't find any unless it's ingest()ed the relevant CMakeLists.txt
        stream first."""
        filters = tuple(re.compile(f).match for f in self.__private_filters)
        for param in self.__modparam(lambda p: p.is_source):
            for tok in param.headers(self.__evaluate, *filters):
                for word in self.__evaluate(tok):
                    assert isinstance(word, str)
                    yield str(self.root.joinpath(word)) + '\n'

def main(args, source, sink, grumble):
    """Driver for the CMakeScanner class.

    Pipe the content of the CMakeLists.txt file in on source (stdin). Name the
    module it supposedly defines on the command line (args) along with the path
    of the CMakeLists.txt file (relative to its module's root). The directory
    part of this filename will be prepended to each public header read from its
    contents. Delivers '\n'-joined names of the headers that define public API
    to sink (stdout.write). May complain about problems to grumble
    (stderr.write)."""
    me = 'cmakescan.py'
    if args and args[0].endswith(me):
        me, args = args[0], args[1:]
    if len(args) < 2 or Path(args[1]).name != 'CMakeLists.txt':
        grumble(f"{me}: Pass name of module and path of CMakeLists.txt on command line\n")
        return 1
    scan = CMakeScanner(args[0], Path(args[1]).parent)
    scan.ingest(source)
    sink(''.join(scan.headers))
    return 0

if __name__ == '__main__':
    import sys
    sys.exit(main(sys.argv, sys.stdin, sys.stdout.write, sys.stderr.write))

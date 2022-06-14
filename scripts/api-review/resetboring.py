#!/usr/bin/env python3
# Usage: see api-review-gen
# Copyright (C) 2022 The Qt Company Ltd.
# SPDX-License-Identifier: LicenseRef-Qt-Commercial OR LGPL-3.0-only OR GPL-2.0-only OR GPL-3.0-only
"""Script to exclude boring changes from the staging area for a commit

We start on a branch off an old release, with headers from a newer
branch checked out (and thus staged) in it; git diff should say
nothing, while git diff --cached describes how the headers have
changed.  We want to separate the boring changes (e.g. to copyright
headers) from the interesting ones (actual changes to the API).

The basic idea is to do an automated git reset -p that discards any
hunk entirely in the copyright header (recognized by its $-delimited
end marker) and, for any other hunks present, checks for certain
standard boring changes that we want to ignore.  If such changes are
present, the hunk is replaced by one that omits the given boring
changes; otherwise, the hunk is left alone.  Once we are done, git
diff --cached should contain nothing boring and git diff should be
entirely boring.  Only git's staging area is changed.

This script emits to stdout the names of files that should be restored
to their prior version (i.e. as in the old release; for files from the
newer branch, this should remove them); it is left to the script
driving this one (api-review-gen) to act on that.  Passing --disclaim
as a command-line option ensures all changed files with (known
variants on) the usual 'We mean it' disclaimer shall be named in this
output.

Errors and warnings are sent to stderr, not stdout.
Nothing is read from standard input.
"""

# See: https://www.dulwich.io/apidocs/dulwich.html
try:
    from dulwich.repo import Repo
    from dulwich.diff_tree import RenameDetector
except ImportError:
    print('I need the python package dulwich (python-dulwich on Debian).')
    raise

class Selector(object): # Select interesting changes, discard boring.
    """Handles removing boring changes from one file.

    The aim is to remove noise from header diffs, so that reviewers
    can focus on the small amounts of meaningful change and not waste
    time making sense of boring changes - such as declaring a method
    nothrow or constexpr; or changes to copyright headers - just so as
    to be sure they can be ignored.  Here, we automate ignoring those
    changes, so that real changes don't get missed by a reviewer so
    busy skipping over boring changes as to not notice the other
    changes mixed in with them.

    The instance serves as carrier for data needed by all parts of the
    filtering process, which is driven by the .refine() method.  A
    .restore() method is also provided to support putting back a
    deleted file.

    In .refine(), each diff hunk is studied to see whether any of the
    new versions' lines contain fragments that, if missing from the
    corresponding prior line, would indicate a boring change.  The
    Censor tool-class provides the tools used to decide what changes
    are boring.  Its .minimize() represents a line by a token
    sequence, with various 'boring' changes undone, that can be used
    to match a new line with an old, from which it has been derived by
    boring changes (even if the old also contained boring fragments).
    Once an old and new line have been found, that this identifies as
    matching, the .harmonize() will undo, from the new line, only
    those boring changes that are absent from the old, so as to reduce
    the new line to a form matching the old as closely as possible.

    Potential matching old lines are sought anywhere in the same hunk
    of diff as the new line to be matched, to allow for small
    movements and for diff being confused, by distractions, into
    misreporting; however, a line moved so far that its new and old
    forms appear in separate hunks shall not be matched up.  The old
    shall be seen as removed and the new as added, without any tidying
    of the new.  (Note that matching happens within hunks of the gross
    diff, before boring bits are filtered out: it is possible that,
    after filtering out other boring changes, the revised diff you
    actually come to review might bring together in a single hunk the
    old and new lines of a boring change that weren't in the same
    chunk when .refine()ing the original diff.)
    """

    def __init__(self, store, new, old, mode):
        """Set up ready to remove boring changes.

        Requires exactly four arguments:

          store -- the object store for our repo
          new -- sha1 of the new file
          old -- sha1 of the old file
          mode -- access permissions for the compromise file

        When .refine() is subsequently called, a new blob gets added
        to the store with the given mode, based on new but skipping
        boring changes relative to old.
        """
        self.__store, self.__mode = store, mode
        self.__old = self.__get_lines(store, old)
        self.__new = self.__get_lines(store, new)
        self.__headOld = self.__end_copyright(self.__old)
        self.__headNew = self.__end_copyright(self.__new)
        self.__hybrid = [] # A compromise between old and new.

    @staticmethod
    def __get_lines(store, sha1):
        if sha1 is None: return ()
        assert len(sha1) == 40, "Expected 40-byte SHA1 digest as name of blob"
        return tuple(store[sha1].as_raw_string().decode().split('\n'))

    # Note: oldMarker and spdxHeader deliberately obfuscated so tools
    # scanning *this* file aren't mislead by them !
    @staticmethod
    def __end_copyright(seq, oldMarker='_'.join(('$QT', 'END', 'LICENSE$')),
                        spdxHeader='-'.join(('SPDX', 'License', 'Identifier:'))):
        """Line number just after the end of the copyright banner"""
        for i, line in enumerate(seq, 1):
            if spdxHeader in line:
                return i
            if oldMarker in line:
                return i + 2
        return 0

    from difflib import SequenceMatcher
    # Can we supply a useful function isjunk, detecting pure-boring
    # lines, in place of None ?
    def __get_hunks(self, context, isjunk=None, differ=SequenceMatcher):
        return differ(isjunk, self.__old, self.__new).get_grouped_opcodes(context)
    del SequenceMatcher

    def refine(self, context=3):
        """Index entry for new, with its boring bits skipped.

        Single optional argument, context, is the number of lines of
        context to include at the start and end of each hunk of
        change; it defaults to 3.  Returns a dulwich IndexEntry
        representing the old file with the new file's interesting
        changes applied to it.
        """
        doneOld = doneNew = 0 # lines consumed already
        copy, digest = self.__copy, self.__digest
        for hunk in self.__get_hunks(context):
            # See __digest() for description of what each hunk is.  A
            # typical hunk starts and ends with an 'equal' block of
            # length context; however, the first in a file might not
            # start thus, nor need the last in a file end thus.
            # Between hunks, there is a tacit big 'equal' block;
            # likewise before the first and after the last.
            block = hunk.pop(0)
            tag, startOld, endOld, startNew, endNew = block
            if doneOld < startOld or doneNew < startNew:
                copy('implicit', doneOld, startOld, doneNew, startNew)
                # doneOld, doneNew = startOld, startNew
            if tag == 'equal':
                copy(*block)
                # doneOld, doneNew = endOld, endNew
            else: # put the block back to process as normal:
                hunk.insert(0, block)

            block = hunk.pop()
            tag, startOld, endOld, startNew, endNew = block
            # Must read last block before calling digest, which modifies hunk.
            if tag == 'equal':
                digest(hunk)
                copy(*block)
            else:
                # File ends in change; put it back to process as normal:
                hunk.append(block)
                digest(hunk)
            doneOld, doneNew = endOld, endNew

        if doneOld < len(self.__old) or doneNew < len(self.__new):
            copy('implicit', doneOld, len(self.__old), doneNew, len(self.__new))

        return self.__as_entry('\n'.join(self.__hybrid), self.__mode)

    from dulwich.index import IndexEntry
    @staticmethod
    def __index_entry(mode, size, blobid, entry=IndexEntry):
        """Wrap IndexEntry to cope with variably many entries in tuple.

        Up to (at least) version 0.20.15, there were ten entries in
        the tuple; but 0.20.23-1 has an eleventh entry; and a
        namedtuple doesn't support leaving out entries to give them a
        default value.
        """
        # (ctime, mtime, dev, ino, mode, uid, gid, size, sha, flags [, extraflags])
        seq = ((0, 0), (0, 0), 0, 0, mode, 0, 0, size, blobid)
        seq += (len(entry._fields) - len(seq)) * (0,)
        return entry(*seq)
    del IndexEntry

    from dulwich.objects import Blob
    def __as_entry(self, text, mode,
                   blob=Blob.from_string):
        """Turn a file's proposed contents into an IndexEntry.

        The returned IndexEntry's properties are mostly filler, as
        only the sha1 and mode are actually needed to update the index
        (along with the name, which caller is presumed to handle).
        """
        dull = blob(text.encode())
        assert len(dull.id) == 40
        self.__store.add_object(dull)
        return self.__index_entry(mode, len(text), dull.id)
    del Blob

    @classmethod
    def restore(cls, blob, mode):
        """Index entry for a specified extant blob.

        Requires exactly two arguments (do *not* pass a third):

          blob -- the Blob object describing the extant blob
          mode -- the mode to be used for this object

        Can be used to put back a deleted file.
        """
        assert len(blob.id) == 40, blob.id
        return cls.__index_entry(mode, len(blob.as_raw_string()), blob.id)

    def __copy(self, tag, startOld, endOld, startNew, endNew):
        assert tag in ('equal', 'implicit'), tag
        assert endOld - startOld == endNew - startNew, \
            'Unequal %s block lengths' % tag
        assert self.__old[startOld:endOld] == self.__new[startNew:endNew], \
            "Unequal %s blocks" % tag
        self.__hybrid += self.__new[startNew:endNew]

    def __digest(self, hunk):
        """Remove everything boring from a hunk.

        This is where the real work gets done.  Single argument, hunk,
        is a list of 5-tuples, (tag, startOld, endOld, startNew,
        endNew), describing a single hunk of the difference between
        two files.  Each relates a range of lines in the old file to a
        range of lines in the new: each range is expressed as
        start:end indices (starting at 0) in each file, with the tag -
        replace, delete, insert or equal - expressing the relation
        between them.  We need to identify boring changes and discard
        or undo them.

        Note that a boring change that difflib.py has mis-described,
        putting the original and final lines in different hunks, won't
        be caught; but, as long as they're in the same hunk (even if
        in different blocks of it), this code aims to catch them and
        undo (only) the boring parts.
        """
        tag, startOld, endOld, startNew, endNew = hunk.pop(0)
        # First deal with copyright header changes: always boring
        while endNew <= self.__headNew and endOld <= self.__headOld:
            if tag == 'equal':
                # Stricly: we should copy from old; but it makes no difference:
                self.__copy(tag, startOld, endOld, startNew, endNew)
            else:
                # discard the new version
                self.__hybrid += self.__old[startOld:endOld]

            if not hunk: return # completely digested already :-)
            tag, startOld, endOld, startNew, endNew = hunk.pop(0)

        if tag == 'equal': # Non-issue, as for fully in copyright:
            self.__copy(tag, startOld, endOld, startNew, endNew)
        else:
            if startNew < self.__headNew and startOld < self.__headOld:
                # This hunk is *partially* copyright.
                # Take copyright header part from old, ...
                if endOld >= self.__headOld:
                    self.__hybrid += self.__old[startOld:self.__headOld]
                    startOld, startNew = self.__headOld, self.__headNew
                    # <Kludge>: before the SPDX conversion, some copyright
                    # headers sequed straight into a "generated file" banner, so
                    # a comment start was inserted.
                    tail = self.__new[startNew]
                    if (self.__hybrid[-1] == '**'
                        and tail.startswith('/*') and tail.rstrip('*') == '/'
                        and self.__new[startNew + 1] == self.__old[startOld]):
                        # Skip over the comment marker, tail.
                        startNew += 1
                    # </Kludge> (except for the next line's >= to accommodate the kludge)
                assert endOld > startOld or endNew >= startNew
                # ... put the (rest of the) block back in the queue:
            hunk.insert(0, (tag, startOld, endOld, startNew, endNew))

        if not hunk: return # completely digested already :-)

        # The hybrid we'll use for the rest (but we'll modify it, in a bit):
        hybrid = list(self.__new[hunk[0][3]:hunk[-1][4]])
        # Tools to remove boring differences:
        bore = self.Censor()

        # Associate each line, involved in either side of the change,
        # with a canonical form; and some in old with their .strip():
        change, origin, unstrip = {}, {}, {}
        for line in set(hybrid):
            seq = []
            for mini in bore.minimize(line):
                if bore.join(line, mini) != line:
                    seq.append(mini)
            if seq:
                change[line] = tuple(seq)
            # else: line contains no boring changes
        for line in self.__old[hunk[0][1]:hunk[-1][2]]:
            for mini in bore.minimize(line):
                try: seq = origin[mini]
                except KeyError: seq = origin[mini] = []
                seq.append(line)
            # Interesting lines might have merely changed indentation:
            if set(line).difference('{\t \n};'):
                key = line.strip()
                try: was = unstrip[key]
                except KeyError: unstrip[key] = line
                else:
                    # If distinct lines have same .strip(), 'fixing'
                    # indent for them may add more diff than it
                    # removes; so use .get()'s default, None.
                    if was is not None and was != line:
                        unstrip[key] = None

        for i, new in enumerate(hybrid):
            old = unstrip.get(new.strip())
            if old is not None: # boring indent change:
                assert old.strip() == new.strip()
                hybrid[i] = old
                continue

            old = tuple(origin[m] for m in change.get(new, ()) if m in origin)
            if old:
                assert all(old), 'Every value of origin is a non-empty list'
                # TODO: chose which entry in old to use, if more than
                # one; and which line in that entry to use, if more
                # than one.
                hybrid[i] = bore.harmonize(old[0][0], new)
                # Until then, use the first list in old; and use its
                # entries in hybrid in the order they had in old (but,
                # to be on the safe side, don't remove from list;
                # cycle to the back, in case new has more than old):
                old[0].append(old[0].pop(0))
                continue

            # TODO: see if any key of origin is kinda similar to new.
            # Not crucial: the API has changed, so filtering out the
            # boring parts won't save the need to review the line,
            # although it would remove a distraction.

        assert len(hybrid) == hunk[-1][4] - hunk[0][3]
        self.__hybrid += hybrid

    class Censor (object): # knows how to be boring
        """Detects and eliminates boring changes.

        Public methods:
          minimize() -- Express line as a canonical token tuple.
          join() -- Recombine tokens, guided by a line.
          harmonize() -- Make one line as much like another as we can.
        Each only makes boring changes.

        Boring changes always happen at a tokenized level, so
        manipulate lines in tokenized form for ease of recognising and
        editing out boring bits.  Use .minimize() to tokenize; then
        .join() knows how to stitch the surviving tokens back
        together, following the form of the original line as far as
        possible.  The prior code may contain some boring parts, that
        we don't want to remove from the new version (else we'd get a
        spurious diff out of that); use harmonize() to remove what's
        boring from a new line, but keeping any of it that's present
        in the old line.

        Externally visible tokenizations (from minimize) are tuples of
        string fragments (with no space in them); internally, some
        tokens in the tuple may themselves be tuples, indicating that
        any entry in that token may be used in place of it, with a
        None entry meaning the whole token is optional.  Every
        externally visible tokenization is a legal internal
        tokenization; .join() accepts either kind.
        """

        @classmethod
        def minimize(cls, text):
            """Reduce text to a minimal sequence of tokens.

            Takes one required argument, text.  Yields tuples of
            tokens; each such tuple characterizes what's interesting
            in the line; usually there's only one, but some recipes
            may allow several.

            Splits text into tokens and applies all our know recipies
            for boring changes to it, reducing to a canonical form.
            Two lines should share a minimal form precisely if the
            only differences between them are boring.
            """
            tokens = cls.__split(text)
            # FIXME: if several recipes apply, the returned selection
            # of variants should represent the result of applying each
            # subset of those recipes; this includes the case of
            # applying one recipe repeatedly, where each candidate
            # application may be included or omitted independently.
            # But this would complicate harmonize() ...
            for test, purge in cls.recipe:
                if test(tokens):
                    tokens = purge(tokens)

            return cls.__iter_variants(tuple(tokens))

        @classmethod
        def __iter_variants(cls, tokens):
            """Yield all variants on a token sequence.

            If any token is a tuple, instead of a simple string, yield
            each variant on the tokens, replacing each such tuple by
            each of its entries or omitting its contribution for a
            None entry, if it has one.
            """
            for ind, here in enumerate(tokens):
                if isinstance(here, tuple):
                    head, tail = tokens[:ind], tokens[ind + 1:]
                    for it in here:
                        mid = () if it is None else (it,) # omit optional
                        for rest in cls.__iter_variants(tail):
                            yield head + mid + rest
                    break # Out of outer for, bypassing its else.
            else:
                yield tokens

        @classmethod
        def harmonize(cls, old, new):
            """Return new, cleaned in whatever ways make it more like old."""
            # If old and new have a common "plausible precursor", the change is all boring:
            if any(candidate in cls.minimize(old) for candidate in cls.minimize(new)):
                return old

            olds, news = cls.__split(old), cls.__split(new)
            for test, purge in cls.recipe:
                if test(news) and not test(olds):
                    news = purge(news)
            return cls.join(old, news)

        # Punctuation at which to split, long tokens before their prefixes:
        cuts = ( '...', '<<=', '>>=',
                 '//', '/*', '*/', '##', '::',
                 # Be sure that // precedes /= (see // = default)
                 '<<', '>>', '==', '!=', '<=', '>=', '&&', '||', '[[', ']]',
                 '+=', '*=', '-=', '/=', '&=', '|=', '%=', '->',
                 '#', '<', '>', '!', '?', ':', ',', '.', ';',
                 '=', '+', '-', '*', '/', '%', '|', '&', '^', '~',
                 '(', ')', '[', ']', '{', '}', '"', "'" )

        @classmethod
        def __split(cls, line):
            """Crudely tokenize: line -> tuple of string fragments"""
            tokens = line.strip().split()
            i = len(tokens)
            while i > 0:
                i -= 1
                word = tokens[i]

                if word in cls.cuts: continue
                for cut in cls.cuts:
                    if cut not in word: continue

                    bits = iter(word.split(cut))
                    # Shouldn't raise StopIteration, because cut was in word:
                    ind = next(bits)
                    if ind:
                        tokens[i] = ind # replacing word
                        i += 1 # insert the rest after it
                    else:
                        del tokens[i] # we'll start inserting where it was

                    for ind in bits:
                        tokens.insert(i, cut)
                        i += 1
                        if ind:
                            tokens.insert(i, ind)
                            i += 1
                    # We've replaced word in tokens; now process its
                    # fragments: index i points just beyond the last.
                    break

            assert all(tokens), 'No empty tokens'
            return tokens

        @classmethod
        def join(cls, orig, tokens):
            """Stitch tokens back together, guided by orig.

            Combine tokens with spacing so as to match orig as closely
            as possible.
            """
            # As we scan orig, we trim what we've scanned.
            text = '' # Our synthesized replacement for orig, made of tokens.
            copy = True # Do text and our last chomp off orig end the same way ?
            for j, word in enumerate(tokens):
                assert word, ("__split() never makes empty tokens", tokens, j)
                # How much space does orig start with ?
                indent = len(orig) - len(orig.lstrip())
                tail = orig[indent:]
                if isinstance(word, tuple):
                    best = None
                    for it in word:
                        if it is None or tail.startswith(it):
                            word = it
                            break
                        elif it in tail and best is None:
                            best = it
                    else: # if we didn't break
                        if best is not None:
                            word = best
                        else: # Word is an insertion: use first variant offered.
                            word = word[0]
                    if word is None:
                        # token is optional, no variant of it appears in orig; skip
                        continue

                # Is word the next thing after that ?
                if tail.startswith(word):
                    tail = tail[len(word):]
                    # Would word have been split around, here ?
                    if (word in cls.cuts
                        or ((not tail or tail[0].isspace()
                             or any(tail.startswith(c) for c in cls.cuts))
                            # This condition  is different in the loop below:
                            and (copy or indent
                                 or not text or text[-1].isspace()
                                 or any(text.endswith(c) for c in cls.cuts)))):
                        text += orig[:indent] + word
                        orig, copy = tail, True
                        continue

                # Did we insert word or drop some of orig ?  (A replace shall be
                # handled as an insert then a drop.)  For drop:
                # a) word must appear later than where we just checked; and
                offset = orig.find(word, indent + 1)
                # b) later (non-tuple) tokens that do appear in orig should do so later.
                rest = [w for w in tokens[j + 1:] if not isinstance(w, tuple) and w in orig]
                # Otherwise, assume word has been inserted.
                # NB: offset is either < 0 or > indent, so definitely not 0.
                tail = orig[offset + len(word):] if offset > 0 else ''
                while offset > 0 and all(w in tail for w in rest):
                    # Probably dropped some of orig - be persuaded if
                    # word would have been split around, here.

                    # What we've maybe dropped, give or take some space:
                    cut = orig[:offset] # Definitely not empty.

                    # Would __split() have split around word, here ?
                    if (word in cls.cuts
                        or ((not tail or tail[0].isspace()
                             or any(tail.startswith(c) for c in cls.cuts))
                            and (cut[-1].isspace() or
                                 any(cut.endswith(c) for c in cls.cuts)))):
                        # Believe we dropped some of orig:
                        if not text or not (copy or indent
                                            or text[-1].isalnum() == word[0].isalnum()):
                            pad = ''
                        elif indent and not cut[-indent:].isspace():
                            pad = cut[:indent]
                        else:
                            indent = len(cut) - len(cut.rstrip())
                            pad = cut[-indent:] if indent else ''

                        text += pad + word
                        orig, copy = tail, True
                        # So we're now done with this word.
                        break # Bypass the while's else clause

                    # Word and all tokens after it do appear in
                    # orig[offset:], but word's first appearance
                    # wouldn't have been split out; loop to look for a
                    # later appearance that would.
                    offset = orig.find(word, offset + 1)
                    tail = orig[offset + len(word):] if offset > 0 else ''

                else:
                    # We didn't break out of that; assume word is an insertion.
                    copy = False
                    if indent:
                        text += orig[:indent]
                        indent = 0
                    elif text and text[-1].isalnum() and word[0].isalnum():
                        text += ' '
                    text += word
                    if not indent and word[-1].isalnum() and orig and orig[0].isalnum():
                        orig = ' ' + orig # may get discarded in a drop next time round

            return text.rstrip() if orig else text

        def recipe():
            """Generates the sequence of recipes for boring changes.

            Yields various (test, purge) twoples, in which:
            test(tokens) determines whether a given sequence of tokens
            matches the end-state of some known boring change; and
            purge(tokens) returns the prior state that would result in
            the given list of tokens, were the boring change applied.
            The replacement list may include, in place of a single
            token, a tuple of candidates (in which None means the
            token can even be left out) to chose amongst, as described
            in the Censor class doc (internal tokenization).

            This is not a method; it provides a namespace we'll throw
            away when it's been run (as part of executing the class
            body), in which to prepare the various recipes, yielding
            each to be collected into the final sequence used by
            harmonize(), minimize().  That sequence then over-writes
            this transient function's name.

            Future: may want to replace the pairs with objects with
            some simple API, so we can extend it - e.g. to support
            command-line selection of which recipes to use, or to
            report how many hits we saw of each recipe.
            """

            # Fatuous substitutions (see below for Q_DECL_OVERRIDE):
            for pair in (('Q_QDOC', 'Q_CLANG_QDOC'),
                         ('Q_DECL_FINAL', 'final'),
                         (('Q_CONSTEXPR',
                           'Q_DECL_CONSTEXPR',
                           'Q_RELAXED_CONSTEXPR',
                           'Q_DECL_RELAXED_CONSTEXPR'), 'constexpr'),
                         ('QT_HAS_BUILTIN', '__has_builtin'),
                         ('QT_HAS_FEATURE', '__has_feature'),
                         ('QT_HAS_ATTRIBUTE', '__has_attribute'),
                         ('QT_HAS_CPP_ATTRIBUTE', '__has_cpp_attribute'),
                         ('QT_HAS_INCLUDE', '__has_include'),
                         ('QT_HAS_INCLUDE_NEXT', '__has_include_next'),
                         ('Q_ALIGNOF', 'alignof'),
                         ('Q_DECL_ALIGN', 'alignas'),
                         ('QVector', 'QList'),
                         ('QLatin1String', 'QLatin1StringView'),
                         ('qSwap', 'qt_pointer_swap'),
                         ):
                def test(words, k=pair[1]):
                    return k in words
                def purge(words, p=pair):
                    return [p[0] if w == p[1] else w for w in words]
                yield test, purge

            # Don't ignore constexpr or nothrow; can't retract once added to an API.
            # Don't ignore explicit; it matters.
            # Words to ignore:
            for key in ('Q_NORETURN', 'Q_CONSTINIT',
                        'Q_DECL_CONST_FUNCTION', 'Q_ALWAYS_INLINE'):
                def test(words, k=key):
                    return k in words
                def purge(words, k=key):
                    return [w for w in words if w != k]
                yield test, purge

            # Can at least ignore inline when given with body:
            pair = ('inline', ';')
            def test(tokens, p=pair):
                return p[0] in tokens and p[1] not in tokens
            def purge(tokens, p=pair):
                return [w for w in tokens if w != p[0]]
            yield test, purge
            # TODO: however, it's actually the *reverse* of this change
            # that's boring; and the present infrastructure doesn't know
            # how to process that.  An undo method, reverse of purge,
            # could let harmonize do this; needs new as well as old, to
            # guide where to add entry to old.

            # Would like to
            # s/QtPrivate::QEnableIf<...>::Type/std::enable_if<...>::type/
            # but the brace-matching is a bit much for this parser; and it
            # tends to get split across lines anyway ...

            # Filter out various common end-of-line comments:
            for sought in (('//', '=', 'default'), ('//', 'LCOV_EXCL_LINE')):
                def test(tokens, sought=sought, size=len(sought)):
                    return tuple(tokens[-size:]) == sought
                def purge(tokens, size=len(sought)):
                    return tokens[:-size]
                yield test, purge

            # QLatin1Char('x') -> u'x'
            def find(tokens):
                start = 0
                try:
                    close = u = tokens.index('u', start)
                    if tokens[u + 1] == "'" and "'" in tokens[u + 2:][:2]:
                        close = u + (2 if tokens[u + 2] == "'" else 3)
                        yield u, close
                    start = close + 1
                except ValueError:
                    pass
            def test(tokens, seek=find):
                for pair in seek(tokens):
                    return True
                return False
            def edit(tokens, seek=find):
                for u, c in seek(tokens):
                    yield u, c + 1, ('QLatin1Char', '(') + tuple(tokens[u + 1:c + 1]) + (')',)
            def purge(tokens, work=edit):
                edits = list(work(tokens))
                while edits:
                    start, stop, replace = edits.pop()
                    tokens[start : stop] = replace
                return tokens
            yield test, purge

            # QVariant::value<> -> qvariant_cast<>
            # expr.value<type>() -> qvariant_cast<type>(expr) or
            # expr->value<type>() -> qvariant_cast<type>(*expr)
            # This code is only adequate for simple expr and type: and
            # is only relevant to bodies of inlines or macros, not in
            # the APIs we're reviewing.
            swap = (('value', '<', None, '>', '(', ')'),
                    ('qvariant_cast', '<', None, '>', '(', None, ')'))
            def find(tokens, sought=swap[1]):
                start = 0
                try:
                    while start + len(sought) < len(tokens):
                        last = match = tokens.index(sought[0], start)
                        if tokens[match + 1] == sought[1]:
                            try:
                                close = tokens.index(sought[3], match + 2)
                                if tokens[close + 1] == sought[4]:
                                    last = tokens.index(sought[6], close + 2)
                                    yield (match, close, last)
                            except ValueError:
                                pass
                        start = last + 1
                except ValueError:
                    pass
            def test(tokens, seek=find):
                # If we have any matches say yes:
                for triad in seek(tokens):
                    return True
                return False
            def edit(tokens, replace=swap[0], seek=find):
                for match, mid, end in seek(tokens):
                    cast = tuple(tokens[match + 2 : mid])
                    if tokens[mid + 2] == '*':
                        dot, obj = '->', tokens[mid + 3 : end]
                    else:
                        dot, obj = '.', tokens[mid + 2 : end]
                    yield match, end + 1, tuple(obj) + (dot,) + replace[:2] + cast + replace[3:]
            def purge(tokens, work=edit):
                edits = list(work(tokens))
                while edits:
                    start, stop, replace = edits.pop()
                    tokens[start : stop] = replace
                return tokens
            yield test, purge

            # qSwap(x, y) -> x.swap(y) is boring
            # if only because it's always in a function body, not an API.
            swap = (('qSwap', '(', None, ',', None, ')'),
                    (None, '.', 'swap', '(', None, ')'))
            def find(tokens, sought=swap[1]):
                start = 0
                try:
                    while start + len(sought) < len(tokens):
                        close = match = tokens.index(sought[1], start + 1)
                        if tuple(tokens[match + 1:][:2]) == sought[2:][:2]:
                            try:
                                close = tokens.index(sought[5], match + 3)
                                if sought[3] not in tokens[match + 3:close]:
                                    yield (match, close)
                            except ValueError:
                                pass
                        start = close + 1
                except ValueError:
                    pass
            def test(tokens, seek=find):
                # If we have any matches say yes:
                for triad in seek(tokens):
                    return True
                return False
            def edit(tokens, replace=swap[0], seek=find):
                for dot, close in seek(tokens):
                    assert 0 < dot < close < len(tokens)
                    this = tokens[dot - 1]
                    other = tuple(tokens[dot + 3 : close])
                    yield dot - 1, close + 1, replace[:2] + (this, replace[3]) + other + replace[5:]
            def purge(tokens, work=edit):
                edits = list(work(tokens))
                while edits:
                    start, stop, replace = edits.pop()
                    tokens[start : stop] = replace
                return tokens
            yield test, purge

            # Complications (involving optional tokens or tokens with
            # alternate forms) should go after all others, to avoid
            # needlessly exercising them:

            # 6.0.0: Q_STATIC_ASSERT(_X)? -> static_assert
            # Since it accepts either one or two parameters, we'd need
            # to parse its parameter list to work out which it came
            # from; too messy so kludge:
            def test(words):
                return 'static_assert' in words
            def purge(words):
                # Longer one first, or a prefix match in join() goes wrong:
                return [('Q_STATIC_ASSERT_X', 'Q_STATIC_ASSERT')
                        if word == 'static_assert' else word
                        for word in words]
            yield test, purge

            # Used repeatedly below; iterates indices at which key starts in words:
            def scan(words, key):
                ind = -1
                try:
                    while True:
                        ind = words.index(key[0], ind + 1)
                        if len(words) < ind + len(key):
                            break # Can't possibly match here, or later
                        if all((words[i + ind] in tok
                                if isinstance(tok, tuple) else
                                words[i + ind] == tok)
                               for i, tok in enumerate(key)):
                            yield ind
                            ind += len(key) - 1
                except ValueError:
                    pass # when .index() doesn't find key[0]

            # 5.10: common switch from while (0) to while (false)
            # 5.12: Q_DECL_EQ_DELETE -> = delete
            # 5.14: qMove -> std::move, Q_DECL_NOEXCEPT_EXPR(...) -> noexcept(...)
            # 6.4: Q_FOREVER -> for (;;)
            for swap in ((('while', '(', '0', ')'), ('while', '(', 'false', ')')),
                         (('Q_FOREVER',), ('for', '(', ';', ';', ')')),
                         (('Q_DECL_EQ_DELETE', ';'), ('=', 'delete', ';')),
                         (('qMove',), ('std', '::', 'move')),
                         (('qSwap',), ('std', '::', 'swap')),
                         (('Q_REQUIRED_RESULT',), ('[[', 'nodiscard', ']]')),
                         # Needs to happen before handling of Q_DECL_NOEXCEPT
                         # (as both replace "noexcept"):
                         # Gets complicated by the first case being common:
                         (('Q_DECL_NOEXCEPT_EXPR', '(', 'noexcept', '('),
                          ('noexcept', '(', 'noexcept', '(')),
                         (('Q_DECL_NOEXCEPT_EXPR', '(', '('), ('noexcept', '(', '(')),
                         ):
                def test(words, get=scan, key=swap[1]):
                    for it in get(words, key):
                        return True
                    return False
                def purge(words, pair=swap, get=scan):
                    offset, step = 0, len(pair[0]) - len(pair[1])
                    for ind in get(words, pair[1]):
                        ind += offset # Correct for earlier edits
                        words[ind : ind + len(pair[1])] = pair[0]
                        offset += step # Update the correction
                    return words
                yield test, purge

            # Multi-step transitions (oldest first in each tuple):
            for seq in (('0', 'Q_NULLPTR', 'nullptr'),
                        # Needs to happen after handling of Q_DECL_NOEXCEPT_EXPR():
                        (None, 'Q_DECL_NOTHROW', 'Q_DECL_NOEXCEPT', 'noexcept'),
                        # 6.0 (at Lars's request, because we had a lot of them):
                        # simply adding noexcept is boring (hence None).
                        ):
                for key in seq[2 if seq[0] is None else 1:]:
                    def test(words, z=key):
                        return z in words
                    def purge(words, z=key, s=seq):
                        return [s if w == z else w for w in words]
                    yield test, purge

            # Used by next two #if-ery mungers:
            def find(words, key):
                assert None in key # so result *does* get set if we succeed
                if len(words) < len(key):
                    return None

                for pair in zip(words, key):
                    word, k = pair
                    if k is None:
                        if any(tok is not None and
                               all(x.isalnum() for x in tok.split('_'))
                               for tok in (word if isinstance(word, tuple) else (word,))):
                            result = word
                        else:
                            return None
                    elif word != k:
                        return None

                # Didn't return early: so matched (and result *did* get set).
                return result, len(key)

            # 6.0: defined(QT_OPENGL_ES*) -> QT_CONFIG(opengles*)
            opengls = { 'opengles2': ('QT_OPENGL_ES_2', 'QT_OPENGL_ES'),
                        'angle': 'QT_OPENGL_ES_2_ANGLE',
                        'opengles3': 'QT_OPENGL_ES_3',
                        'opengles31': 'QT_OPENGL_ES_3_1',
                        'opengles32': 'QT_OPENGL_ES_3_2' }

            # 5.10: #ifndef QT_NO_XXX -> #if QT_CONFIG(xxx)
            swap = (('#', 'ifndef', None), ('#', 'if', 'QT_CONFIG', '(', None, ')'))
            def test(words, get=find, key=swap[1]):
                if get(words, key) is None:
                    return False
                words = words[len(key):] # OK if, after QT_CONFIG(), nothing but comment:
                if not words or words[0] == '//':
                    return True
                return words[0] == '/*' and '*/' not in words[:-1]
            def purge(words, get=find, pair=swap, gls=opengls):
                name, length = get(words, pair[1])
                words[:length] = (['#', 'ifdef', gls[name]]
                                  if name in gls else
                                  [x or 'QT_NO_' + name.upper() for x in pair[0]])
                return words
            yield test, purge

            # Canonicalise so that (among other things) QT_CONFIG matches either way:
            # #if !defined(...) -> #ifndef ...
            for swap in ( (('#', 'if', '!', 'defined', '(', None, ')'),
                           ('#', 'ifndef', None)),
                          # ... and the same for #if defined(...) -> #ifdef ...
                          (('#', 'if', 'defined', '(', None, ')'),
                           ('#', 'ifdef', None)) ):
                def test(words, get=find, key=swap[1]):
                    return get(words, key) is not None
                def purge(words, get=find, pair=swap):
                    name, length = get(words, pair[1])
                    words[:length] = [x or name for x in pair[0]]
                    return words
                yield test, purge

            # Used both by #if/#elif and by #endif processing:
            def find(words, keys, gls=opengls):
                if (len(words) < len(keys)
                    or any(a != b for a, b in zip(words, keys[:-2]))
                    or words[len(keys) - 2] not in keys[-2]):
                    return
                ind, key = 0, keys[-1]
                while True:
                    try:
                        ind = words.index(key, ind)
                    except ValueError:
                        break
                    if ind < 0 or len(words) <= ind + 3:
                        break
                    ind += 1
                    if words[ind] != '(' or words[ind + 2] != ')':
                        continue
                    ind += 1
                    if isinstance(words[ind], tuple):
                        pass # is the result of earlier, equivalent, handling
                    elif words[ind] in gls:
                        yield ind, gls[words[ind]]
                    elif words[ind].isalnum():
                        yield ind, 'QT_NO_' + words[ind].upper()
                    ind += 1

            # Also match QT_CONFIG() when part-way through a #if or #elif condition:
            sought = ('#', ('if', 'elif'), 'QT_CONFIG')
            def test(words, get=find, keys=sought):
                for it in get(words, keys):
                    return True
                return False
            def purge(words, get=find, keys=sought):
                # Reverse iterate, as some replacements shorten, so shift later indices
                for ind, name in reversed(tuple(get(words, keys))):
                    assert words[ind - 2] == 'QT_CONFIG'
                    assert words[ind + 1] == ')'
                    words[ind - 2 : ind + 1] = (
                        ['!', 'defined', '(', name]
                        if not isinstance(name, tuple) and name.startswith('QT_NO_') else
                        ['defined', '(', name])
                return words
            yield test, purge

            # Catch similar in #endif-comments:
            sought=('#', 'endif', ('//', '/*'), 'QT_CONFIG')
            def test(words, get=find, keys=sought):
                for it in get(words, keys):
                    return True
                return False
            def purge(words, get=find, keys=sought):
                for ind, name in get(words, keys):
                    assert words[ind - 2] == 'QT_CONFIG'
                    words[ind - 2 : ind + 2] = [ ('!', None), name ]
                return words
            yield test, purge

            # Ignore parentheses on #if ... defined(blah) ...:
            def find(words):
                """Iterate indices in words of each blah in 'defined(blah)'"""
                if any(a != b for a, b in zip(words, ('#', 'if'))):
                    return
                ind, ans = 0, []
                while True:
                    try:
                        ind = words.index('defined', ind)
                    except ValueError:
                        break
                    if ind < 0 or len(words) <= ind + 3:
                        break
                    ind += 1
                    if words[ind] != '(' or words[ind + 2] != ')':
                        continue
                    ind += 1
                    if isinstance(words[ind], str) and words[ind].isalnum():
                        yield ind
            def test(words, get=find):
                for it in get(words):
                    return True
                return False
            def purge(words, get=find):
                # Remove later tokens before earlier, so indices are still valid until used:
                for keep in reversed(tuple(get(words))):
                    del words[keep + 1]
                    del words[keep - 1]
                return words
            yield test, purge

            # "virtual blah(args)" -> "blah(args) Q_DECL_OVERRIDE" -> "blah(args) override"
            # but allow that virtual might never have been present
            # (hence the support for optional tokens, above)
            swap = ('virtual', ('Q_DECL_OVERRIDE', 'override'))
            def test(words, after=swap[1][1]):
                return after in words
            def purge(words, pair=swap[1]):
                return [pair[0] if w == pair[1] else w for w in words]
            yield test, purge
            def test(words, after=swap[1]):
                return any(s in words for s in after)
            def purge(words, s=swap):
                words = [w for w in words if w not in s[1]]
                # Add virtual at start, if absent, as optional token:
                if s[0] not in words:
                    words.insert(0, (s[0], None))
                return words
            yield test, purge

        # Sequence of (test, purge) pairs to detect boring and canonicalize it away:
        recipe = tuple(recipe())

class Scanner(object): # Support for its .disclaimed()
    __litmus = (
        'This file is not part of the Qt API',
        'This header file may change from version to version without notice, or even be removed',
        'Usage of this API may make your code source and binary incompatible with future versions of Qt',
        )

    @staticmethod
    def __warnPara(paragraph, grmbl):
        lines = ['  ' + s.strip() + '.' for s in paragraph.split('. ') if s]
        lines.insert(0, 'Suspected BC/SC disclaimer not recognized as such:')
        lines.append('') # ensure we end in a newline:
        grmbl('\n'.join(lines))

    @classmethod
    def disclaimed(cls, path, grmbl):
        """Detect the We Mean It (or similar) comment in a C++ file.

        Assumes the comment forms a contiguous sequence of C++-style
        comment lines.  Allows more flexibility than is actually
        observed, mainly because it has to be flexible about the main
        paragraph (there are several variants); being able to support
        flexibility there makes it easy to test the first few lines
        fuzzily."""
        warn, litmus, paragraph = 0, cls.__litmus, ''
        with open(path) as fd:
            for line in fd:
                line = line.strip()
                if line.startswith('//'):
                    line = line[2:].lstrip()
                else: # not a simple C++ comment
                    warn = 0
                    continue

                if warn == 0: # There's always an initial blank line:
                    if line:
                        if line == 'We mean it.' and paragraph.startswith('This file is'):
                            cls.__warnPara(paragraph, grmbl)
                        continue
                    warn = 1

                elif warn == 1:
                    if not line: # There may be several blank lines at the start.
                        continue
                    # Check for banner (may have spaces between letters):
                    if ''.join(line.split()) != 'WARNING':
                        warn = 0
                        continue
                    warn = 2
                    paragraph = ''

                elif warn == 2: # Banner is always underlined with dashes:
                    if any(ch != '-' for ch in line):
                        warn = 0
                        continue
                    warn = 3

                elif line:
                    paragraph += line + ' '
                elif paragraph:
                    # Is this one of our familiar paragraphs ?
                    for sentence in paragraph.split('. '):
                        # Eliminate any irregularities in spacing:
                        if ' '.join(sentence.split()) in litmus:
                            grmbl('Filtered out C++ file with disclaimer: %s\n' % path)
                            return True
                    # Apparently not; but see 'We mean it.' check, above.
                    warn = 0
                # else: blank line before first paragraph

        return False

# Future: we may want to parse more args, query the user or wrap
# talk, complain for verbosity control.
def main(args, hear, talk, complain):
    """Reset boring changes

    See doc-string of this file for outline.

    Required arguments - args, hear, talk and complain -- should,
    respectively, be (or behave as, e.g. if mocking to test) sys.argv,
    sys.stdin, sys.stdout and sys.stderr.  The only command-line
    option supported (in args) is a '--disclaim' flag, to treat as
    boring all changes in files with the standard 'We mean it'
    disclaimer; it is usual to pass this flag.\n"""
    ignore = Scanner.disclaimed if '--disclaim' in args else (lambda p, w: False)

    # We're in the root directory of the module:
    repo = Repo('.')
    store, index = repo.object_store, repo.open_index()
    renamer = RenameDetector(store)
    try:
        # TODO: demand stronger similarity for a copy than for rename;
        # our huge copyright headers (and common boilerplate) make
        # small header files look very similar despite their real
        # content all being quite different.  Probably need to hack
        # dulwich (find_copies_harder is off by default anyway).
        for kind, old, new in \
            renamer.changes_with_renames(store[repo.refs[b'HEAD']].tree,
                                         index.commit(store)):
            # Each of old, new is a named triple of .path, .mode and
            # .sha; kind is the change type, in ('add', 'modify',
            # 'delete', 'rename', 'copy', 'unchanged'), although we
            # shouldn't get the last.  If new.path is None, file was
            # removed, not renamed; otherwise, if new has a
            # disclaimer, it's private despite its name and path.
            if new.path and not ignore(new.path, complain.write):
                assert kind not in ('unchanged', 'delete'), kind
                if kind != 'add':
                    # Filter out boring changes
                    index[new.path] = Selector(store, new.sha, old.sha,
                                               old.mode or new.mode).refine()
            elif old.path: # disclaimed or removed: ignore by restoring
                assert new.path or kind == 'delete', (kind, new.path)
                index[old.path] = Selector.restore(store[old.sha], old.mode)
                talk.write(old.path.decode() + '\n')
                if new.path and new.path != old.path:
                    talk.write(new.path.decode() + '\n')
            else: # new but disclaimed: ignore by discarding
                assert kind == 'add' and new.path, (kind, new.path)
                del index[new.path]
                talk.write(new.path.decode() + '\n')

        index.write()
    except IOError: # ... and any other errors that just mean failure.
        return 1
    return 0

if __name__ == '__main__':
    import sys
    sys.exit(main(sys.argv, sys.stdin, sys.stdout, sys.stderr))

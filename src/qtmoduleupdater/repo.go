/****************************************************************************
**
** Copyright (C) 2019 The Qt Company Ltd.
** Contact: https://www.qt.io/licensing/
**
** This file is part of the repo tools module of the Qt Toolkit.
**
** $QT_BEGIN_LICENSE:GPL-EXCEPT$
** Commercial License Usage
** Licensees holding valid commercial Qt licenses may use this file in
** accordance with the commercial license agreement provided with the
** Software or, alternatively, in accordance with the terms contained in
** a written agreement between you and The Qt Company. For licensing terms
** and conditions see https://www.qt.io/terms-conditions. For further
** information use the contact form at https://www.qt.io/contact-us.
**
** GNU General Public License Usage
** Alternatively, this file may be used under the terms of the GNU
** General Public License version 3 as published by the Free Software
** Foundation with exceptions as appearing in the file LICENSE.GPL3-EXCEPT
** included in the packaging of this file. Please review the following
** information to ensure the GNU General Public License requirements will
** be met: https://www.gnu.org/licenses/gpl-3.0.html.
**
** $QT_END_LICENSE$
**
****************************************************************************/
package main

import (
	"bufio"
	"bytes"
	"fmt"
	"io/ioutil"
	"log"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

type commandWithCapturedOutput struct {
	cmd    *exec.Cmd
	stdout bytes.Buffer
	stderr bytes.Buffer
}

func newCommandWithCapturedOutput(cmd *exec.Cmd) *commandWithCapturedOutput {
	result := &commandWithCapturedOutput{}
	result.cmd = cmd
	result.cmd.Stdout = &result.stdout
	result.cmd.Stderr = &result.stderr
	return result
}

func (c *commandWithCapturedOutput) Run() (string, error) {
	err := c.cmd.Run()
	if err != nil {
		return "", fmt.Errorf("Error running %s: %s\nStdout: %s\nStderr: %s", strings.Join(c.cmd.Args, " "), err, c.stdout.String(), c.stderr.String())
	}
	return c.stdout.String(), err
}

func (c *commandWithCapturedOutput) RunWithSpaceTrimmed() (string, error) {
	output, err := c.Run()
	return strings.TrimSpace(output), err
}

// Repository is a type that wraps various git operations on the given repository on the local disk.
type Repository string

// OID is a git object identifier, in the form of a SHA1 check-sum.
type OID string

// RepoURL returns a clone/fetch URL for the given project.
func RepoURL(project string) (*url.URL, error) {
	gerritConfig := struct {
		URL  string
		Port string
	}{
		"codereview.qt-project.org",
		"29418",
	}
	repo := &url.URL{}
	repo.Host = gerritConfig.URL + ":" + gerritConfig.Port
	repo.Path = "/" + project
	repo.Scheme = "ssh"
	return repo, nil
}

// RepoPushURL returns a URL to use for pusing changes to the project.
func RepoPushURL(project string) (*url.URL, error) {
	pushURL, err := RepoURL(project)
	if err != nil {
		return nil, err
	}
	user := os.Getenv("GIT_SSH_USER")
	if user != "" {
		pushURL.User = url.User(user)
	}
	return pushURL, nil
}

// OpenRepository is used to create a new repository wrapper for the specified project.
// If the repository doesn't exist yet, it will be cloned.
func OpenRepository(project string) (Repository, error) {
	reposLocation := "git-repos"
	repoPath := filepath.Join(reposLocation, project)
	if _, err := os.Stat(repoPath); os.IsNotExist(err) {
		url, err := RepoURL(project)
		if err != nil {
			return "", err
		}
		log.Printf("Cloning missing repository %s from %s to %s\n", project, url, repoPath)
		cloneCmd := []string{"clone", "--bare"}
		for _, ref := range strings.Split(os.Getenv("QT_CI_REPO_REFERENCES"), ":") {
			path := ref + "/.git/modules/" + strings.Split(project, "/")[1]
			_, err := os.Stat(path)
			if err == nil {
				cloneCmd = append(cloneCmd, []string{"--reference", path}...)
				break
			}
		}
		cloneCmd = append(cloneCmd, []string{url.String(), repoPath}...)
		cmd := exec.Command("git", cloneCmd...)
		if err = cmd.Run(); err != nil {
			return "", err
		}
	}
	return Repository(repoPath), nil
}

func (repo Repository) gitCommand(command string, parameters ...string) *commandWithCapturedOutput {
	parameters = append([]string{"--git-dir=" + string(repo), command}, parameters...)
	return newCommandWithCapturedOutput(exec.Command("git", parameters...))
}

// LookupReference resolves the provided git reference by means of calling rev-parse.
func (repo Repository) LookupReference(ref string) (OID, error) {
	rev, err := repo.gitCommand("rev-parse", ref).RunWithSpaceTrimmed()
	return OID(rev), err
}

// ObjectType denotes the different types of objects stored in a git repository.
type ObjectType int

const (
	// ObjectBlob refers to a pure data object
	ObjectBlob = iota
	// ObjectCommit refers to a git commit
	ObjectCommit
	// ObjectTree refers to a tree if blobs or trees
	ObjectTree
)

// TreeEntry describes the entry of a directory listing in git
type TreeEntry struct {
	Permissions string
	Type        ObjectType
	ID          OID
}

// Tree is data structure representing the output of the git ls-tree command.
type Tree struct {
	Repo    Repository
	ID      OID
	Entries map[string]TreeEntry
}

func (repo Repository) decodeLsTreeOutput(commit OID, output string) (*Tree, error) {
	result := &Tree{
		Repo:    repo,
		ID:      commit,
		Entries: make(map[string]TreeEntry),
	}
	for _, line := range bytes.Split([]byte(output), []byte{0}) {
		if len(line) == 0 {
			continue
		}
		var entry TreeEntry
		modeIndex := bytes.IndexByte(line, ' ')
		if modeIndex == -1 {
			return nil, fmt.Errorf("missing space after permission field while parsing git ls-tree output")
		}
		entry.Permissions = string(line[:modeIndex])

		line = line[modeIndex+1:]

		typeIndex := bytes.IndexByte(line, ' ')
		if typeIndex == -1 {
			return nil, fmt.Errorf("missing space after type field while parsing git ls-tree output")
		}
		typeName := line[:typeIndex]
		switch string(typeName) {
		case "tree":
			entry.Type = ObjectTree
		case "blob":
			entry.Type = ObjectBlob
		case "commit":
			entry.Type = ObjectCommit
		default:
			return nil, fmt.Errorf("unexpected entry type %s while parsing git ls-tree output", typeName)
		}

		line = line[typeIndex+1:]

		objectIndex := bytes.IndexByte(line, '\t')
		if objectIndex == -1 {
			return nil, fmt.Errorf("missing space after entry field while parsing git ls-tree output")
		}
		entry.ID = OID(string(line[:objectIndex]))

		name := string(line[objectIndex+1:])

		result.Entries[name] = entry
	}
	return result, nil
}

// ListTree retrieves a (non-recursive) directory listing of the specified commit.
func (repo Repository) ListTree(commit OID) (*Tree, error) {
	output, err := repo.gitCommand("ls-tree", "-z", string(commit)).Run()
	if err != nil {
		return nil, err
	}
	return repo.decodeLsTreeOutput(commit, output)
}

// ListTreeWithPath retrieves a (non-recursive) directory listing of the specified commit with the specified path.
func (repo Repository) ListTreeWithPath(commit OID, subPath string) (*Tree, error) {
	output, err := repo.gitCommand("ls-tree", "-z", string(commit), subPath).Run()
	if err != nil {
		return nil, err
	}
	return repo.decodeLsTreeOutput(commit, output)
}

// Fetch retrieves the specified refSpec from the given url. The result is fetched into FETCH_HEAD
// and the value of FETCH_HEAD is returned.
func (repo Repository) Fetch(url *url.URL, refSpec string) (sha1 OID, err error) {
	if fetch := os.Getenv("NO_FETCH"); len(fetch) == 0 {
		cmd := repo.gitCommand("fetch", url.String(), refSpec)
		if _, err = cmd.Run(); err != nil {
			return "", fmt.Errorf("Error running fetch command: %s", err)
		}
	}
	ref, err := repo.LookupReference("FETCH_HEAD")
	if err != nil {
		return "", fmt.Errorf("Error looking up FETCH_HEAD after fetch: %s", err)
	}
	return ref, nil
}

// Push is a wrapper around the git push commit, similar to the Push() function
// but allowing additional options to be passed to the git push invocation.
func (repo Repository) Push(url *url.URL, options []string, commit OID, targetRef string) error {
	refSpec := fmt.Sprintf("%s:%s", commit, targetRef)
	options = append(options, url.String(), refSpec)
	_, err := repo.gitCommand("push", options...).Run()
	return err
}

// LookupBlob returns the byte content of the specified blob object.
func (repo Repository) LookupBlob(object OID) ([]byte, error) {
	output, err := repo.gitCommand("cat-file", "blob", string(object)).Run()
	if err != nil {
		return nil, err
	}
	return []byte(output), nil
}

// IndexEntry represents an entry in the virtual git index directory structure.
type IndexEntry struct {
	Permissions string
	Path        string
	ID          OID
}

// Index is a wrapper around git operations that allow operating on a temporary index.
type Index struct {
	file          *os.File
	repo          Repository
	cachedEntries []IndexEntry
	populated     bool
}

// NewIndex creates a new git index based on a temporary file. Unless you'd like to
// start with an empty tree, you may want to populate the index with ReadTree.
// A newly created index should be freed with Free() at the end of the usage, in order
// to remove the temporary file.
func (repo Repository) NewIndex() (result *Index, err error) {
	result = &Index{}
	result.repo = repo
	result.file, err = ioutil.TempFile("", "")
	if err != nil {
		return nil, err
	}
	result.populated = false
	return result, nil
}

// CommitTree creates a new commit object from the specified tree, along with the specified message and parent commits.
// The new commit id is returned.
func (repo Repository) CommitTree(tree OID, message string, parents ...OID) (OID, error) {
	allParams := make([]string, 0, 1+2*len(parents))
	allParams = append(allParams, string(tree))
	for _, parent := range parents {
		allParams = append(allParams, "-p")
		allParams = append(allParams, string(parent))
	}
	cmd := repo.gitCommand("commit-tree", allParams...)
	cmd.cmd.Stdin = bytes.NewBufferString(message)
	commit, err := cmd.RunWithSpaceTrimmed()
	return OID(commit), err
}

// LogOutput is a wrapper around the git log command.
func (repo Repository) LogOutput(options ...string) ([]string, error) {
	logOutput, err := repo.gitCommand("log", options...).Run()
	if err != nil {
		return nil, err
	}
	var log []string
	scanner := bufio.NewScanner(bytes.NewBufferString(logOutput))
	for scanner.Scan() {
		log = append(log, scanner.Text())
	}
	return log, nil
}

// Free is responsible for deleting the temporary index file.
func (idx *Index) Free() {
	os.Remove(idx.file.Name())
	idx.file = nil
}

func (idx *Index) gitCommandWithIndex(command string, parameters ...string) *commandWithCapturedOutput {
	cmd := idx.repo.gitCommand(command, parameters...)
	cmd.cmd.Env = os.Environ()
	cmd.cmd.Env = append(cmd.cmd.Env, "GIT_INDEX_FILE="+idx.file.Name())
	return cmd
}

func (idx *Index) updateCachedEntries() error {
	idx.cachedEntries = make([]IndexEntry, 0)

	output, err := idx.gitCommandWithIndex("ls-files", "-z", "--stage").Run()
	if err != nil {
		return err
	}
	for _, line := range bytes.Split([]byte(output), []byte{0}) {
		if len(line) == 0 {
			continue
		}
		var entry IndexEntry
		modeIndex := bytes.IndexByte(line, ' ')
		if modeIndex == -1 {
			return fmt.Errorf("missing space after permission field while parsing git ls-files output")
		}
		entry.Permissions = string(line[:modeIndex])
		line = line[modeIndex+1:]

		objectIndex := bytes.IndexByte(line, ' ')
		if objectIndex == -1 {
			return fmt.Errorf("missing space after entry field while parsing git ls-files output")
		}
		entry.ID = OID(string(line[:objectIndex]))
		line = line[objectIndex+1:]

		stageIndex := bytes.IndexByte(line, '\t')
		if stageIndex == -1 {
			return fmt.Errorf("missing space after stage field while parsing git ls-files output")
		}

		entry.Path = string(line[stageIndex+1:])
		idx.cachedEntries = append(idx.cachedEntries, entry)
	}
	return nil
}

// EntryCount returns the number of directory/file entries in the index.
func (idx *Index) EntryCount() int {
	return len(idx.cachedEntries)
}

// EntryByIndex returns the i-th entry in the directory index.
func (idx *Index) EntryByIndex(i int) (*IndexEntry, error) {
	if i < 0 || i >= len(idx.cachedEntries) {
		return nil, fmt.Errorf("Index %v out of range in index (0 - %v)", i, len(idx.cachedEntries))
	}

	return &idx.cachedEntries[i], nil
}

// ReadTree populates the index from the specified tree object. This is implemented by calling git read-tree.
func (idx *Index) ReadTree(tree OID) error {
	_, err := idx.gitCommandWithIndex("read-tree", "--index-output="+idx.file.Name(), string(tree)).Run()
	if err != nil {
		return err
	}
	idx.populated = true
	return idx.updateCachedEntries()
}

// Add adds a new entry to the index or updates an existing one if already present.
func (idx *Index) Add(entry *IndexEntry) error {
	if !idx.populated {
		os.Remove(idx.file.Name())
	}
	_, err := idx.gitCommandWithIndex("update-index", "--add", "--cacheinfo", fmt.Sprintf("%s,%s,%s", entry.Permissions, entry.ID, entry.Path)).Run()
	if err != nil {
		return err
	}
	idx.populated = true
	return idx.updateCachedEntries()
}

// HashObject writes content b as git object to the database and updates the entry.
func (idx *Index) HashObject(entry *IndexEntry, b []byte) error {
	tempfile, err := ioutil.TempFile("", "")
	if err != nil {
		return err
	}
	defer os.Remove(tempfile.Name())

	if _, err := tempfile.Write(b); err != nil {
		return err
	}

	newSha1, err := idx.gitCommandWithIndex("hash-object", "-w", tempfile.Name()).RunWithSpaceTrimmed()
	if err != nil {
		return err
	}

	entry.ID = OID(newSha1)

	return nil
}

// WriteTree writes the index to the git database as a tree object and returns the tree object id.
func (idx *Index) WriteTree() (OID, error) {
	output, err := idx.gitCommandWithIndex("write-tree").RunWithSpaceTrimmed()
	return OID(output), err
}

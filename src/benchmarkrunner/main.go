package main

import (
	"archive/zip"
	"flag"
	"fmt"
	"io"
	"io/ioutil"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	"code.qt.io/qt/qtqa.git/src/goqtestlib"
	"github.com/kardianos/osext"
)

func recordResults(resultsDirectory string, workingDir string) error {
	os.Unsetenv("TESTRUNNER")

	makeCommand := exec.Command("make", "benchmark")
	makeCommand.Stdout = os.Stdout
	makeCommand.Stderr = os.Stderr
	runner := func(extraArgs []string) error {
		arguments := strings.Join(extraArgs, " ")
		benchmarkArgs := os.Getenv("QT_BENCHMARK_ARGS")
		if benchmarkArgs != "" {
			arguments = arguments + " " + benchmarkArgs
		}

		defer goqtestlib.SetEnvironmentVariableAndRestoreOnExit("TESTARGS", arguments)()
		return makeCommand.Run()
	}

	name, err := filepath.Rel(os.Getenv("QT_BENCHMARK_BASE_DIRECTORY"), workingDir)
	if err != nil {
		return fmt.Errorf("Could not determine relative directory: %s", err)
	}
	if name == "." {
		name = "testcase"
	}

	repetitions := 0
	result, err := goqtestlib.GenerateTestResult(name, resultsDirectory, repetitions, runner)
	if err != nil {
		return err
	}

	return os.Rename(result.PathToResultsXML, filepath.Join(resultsDirectory, name+".xml"))
}

func archiveResults(resultsDir string, outputFile io.Writer) error {
	archiver := zip.NewWriter(outputFile)
	defer archiver.Close()

	return filepath.Walk(resultsDir, func(path string, info os.FileInfo, err error) error {
		if info == nil || info.IsDir() {
			return nil
		}

		relativePath, err := filepath.Rel(resultsDir, path)
		if err != nil {
			return err
		}

		sourceFile, err := os.Open(path)
		if err != nil {
			return err
		}
		defer sourceFile.Close()

		header, err := zip.FileInfoHeader(info)
		if err != nil {
			return err
		}
		header.Name = relativePath

		file, err := archiver.CreateHeader(header)
		if err != nil {
			return err
		}

		n, err := io.Copy(file, sourceFile)
		if n != info.Size() {
			return fmt.Errorf("Incorrect number of bytes written to archive for %s: Wrote %v expected %v", path, n, info.Size())
		}
		return err
	})
}

func collectResults(workingDir string) error {
	self, err := osext.Executable()
	if err != nil {
		return fmt.Errorf("Unable to determine current executable name: %s", err)
	}

	resultsDir, err := ioutil.TempDir("", "")
	if err != nil {
		return err
	}
	defer os.RemoveAll(resultsDir)

	os.Setenv("TESTRUNNER", self)
	os.Setenv("QT_BENCHMARK_RECORDING_DIRECTORY", resultsDir)
	os.Setenv("QT_BENCHMARK_BASE_DIRECTORY", workingDir)
	os.Setenv("QT_HASH_SEED", "0")

	var outputFileName string
	flag.StringVar(&outputFileName, "output-file", "results.zip", "Write collected benchmark results into specified file")
	flag.Parse()

	os.Setenv("QT_BENCHMARK_ARGS", strings.Join(flag.Args(), " "))

	makeCommand := exec.Command("make", "benchmark")
	makeCommand.Stdout = os.Stdout
	makeCommand.Stderr = os.Stderr

	if err := makeCommand.Run(); err != nil {
		return fmt.Errorf("Error running make benchmark: %s", err)
	}

	outputFile, err := os.Create(outputFileName)
	if err != nil {
		return fmt.Errorf("Error creating output file: %s", err)
	}
	defer outputFile.Close()

	return archiveResults(resultsDir, outputFile)
}

func appMain() error {
	workingDir, err := os.Getwd()
	if err != nil {
		return fmt.Errorf("Error determining current working directory: %s", err)
	}

	if os.Getenv("QT_BENCHMARK_RECORDING_DIRECTORY") != "" {
		return recordResults(os.Getenv("QT_BENCHMARK_RECORDING_DIRECTORY"), workingDir)
	}

	return collectResults(workingDir)
}

func main() {

	if err := appMain(); err != nil {
		fmt.Printf("%s\n", err)
		os.Exit(2)
	}
}

# Build Reference Cleaner

The Build Reference Cleaner is designed clean up old build references (build refs) in Git repositories.
This will prevent the build refs from accumulating over time.

## Prerequisites

Before using the Build Ref Cleaner, ensure you have the following prerequisites installed on your system:

- Python 2.x (will not work on python 3.x)

## Usage

### Configuration

1. Open `Build_ref_cleaner.py` in a text editor and customize the `_clean_these` list to specify the Git repositories you want to clean:
    (if you have folders with multiple git repositories you can give the path to that folder)

   ```python
   _clean_these = ["path/to/repository1", "path/to/repository2", "path/to/folder_with_git_repos"]
   ```
2. Place the Build_ref_cleaner.py script into a folder where it is able to see all the paths in _clean_these list.

### Running the Script

1. Navigate to the directory where you placed Build_ref_cleaner.py and run the script to clean the build refs:

   ```bash
   cd path/to/folder_with_Build_ref_cleaner
   python Build_ref_cleaner.py
   ```
   or you can give the path to python
   ```bash

   python path/to/folder_with_Build_ref_cleaner/Build_ref_cleaner.py
   ```

   The script will remove old and invalid build refs from the specified repositories or folders.

## Running Tests

The provided unit tests can be executed to ensure the correct behavior of the script:
(These will only test the logic in the functions of the script
but they will not test if git commands themselves are working properly.)
1. Run the tests using Python's unittest framework:

   ```bash
   python -m unittest test_build_ref_cleaner
   ```
## Running Coverage

   If you want to check code coverage you need to install coverage.py first.
   ```bash
   python -m pip install coverage
   ```
   Using coverage

1. Run the unit test with coverage:
   ```bash
   coverage run -m unittest discover
   ```

2. Check the results using coverage report. You can add -m to check the missed lines:
   ```bash
   coverage report -m
   ```

3. For html presentation use coverage html which creates a htmlcov/index.html file.

   ```bash
   coverage html
   ```

4. Open the html file in your browser.

## File Descriptions

- `Build_ref_cleaner.py`: Contains the main logic for cleaning build refs. The script defines functions for interacting with Git repositories, removing old build refs, and managing file paths.

- `test_Build_ref_cleaner.py`: Contains unit tests for the `Build_ref_cleaner.py` script. It uses the `unittest` framework and the `unittest.mock` library for effective testing.

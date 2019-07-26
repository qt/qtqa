PIPENV := ~/.local/bin/pipenv

first:
	$(PIPENV) install

install_dev_dependencies:
	$(PIPENV) install --dev

run:
	$(PIPENV) run ./main.py

production:
	$(PIPENV) run ./main.py --production

oauth:
	$(PIPENV) run ./oauth_dance.py

test: flake8 mypy
	$(PIPENV) run py.test

flake8:
	$(PIPENV) run flake8

coverage:
	$(PIPENV) run py.test --cov-report=term --cov-report=html --cov=.
	xdg-open htmlcov/index.html

mypy:
	$(PIPENV) run mypy --strict --ignore-missing-imports *.py

check: test flake8 mypy

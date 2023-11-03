.PHONY: install
install:
	sudo groupadd benchmarkers
	sudo gpasswd -a $$USER benchmarkers
	sudo install -m 755 sysfiles/prep_bench /usr/local/bin
	sudo install -m 755 sysfiles/unprep_bench /usr/local/bin
	sudo install -m 550 sysfiles/50_bench /etc/sudoers.d

.PHONY: remove
remove:
	sudo groupdel benchmarkers
	sudo rm /usr/local/bin/prep_bench
	sudo rm /usr/local/bin/unprep_bench
	sudo rm /etc/sudoers.d/50_bench

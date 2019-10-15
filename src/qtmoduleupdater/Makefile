
service_start:
	systemd-run --user --on-calendar="*-*-* *:00:00" --same-dir --unit qtmoduleupdater $(MAKE) -d service_iterate

service_stop:
	systemctl --user stop qtmoduleupdater.timer

service_iterate:
	git pull --rebase
	go build
	./qtmoduleupdater -autorun

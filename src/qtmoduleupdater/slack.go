package main

import (
	"bytes"
	"encoding/json"
	"github.com/kardianos/osext"
	"io/ioutil"
	"log"
	"net/http"
	"path/filepath"
)

// SlackConfig describes the format of slack.json for the slack coin integration
type SlackConfig struct {
	WebHookURL string `json:"WebHookURL"`
}

var (
	slackConfig SlackConfig
)

// SlackMessage is the format used to send a message into slack
type SlackMessage struct {
	Text string `json:"text"`
}

func initSlackIntegration() {
	binFolder, err := osext.ExecutableFolder()
	if err != nil {
		log.Println("Unable to get executable folder - Slack integration disabled")
		return
	}
	configFile := filepath.Join(binFolder, "coin-secrets", "submodule_update_bot_alert_hook.json")
	jsonData, err := ioutil.ReadFile(configFile)
	if err != nil {
		log.Println("Could not read coin-secrets/submodule_update_bot_alert_hook.json - Slack integration disabled")
		return
	}
	var cfg SlackConfig
	err = json.Unmarshal(jsonData, &cfg)
	if err != nil {
		log.Println("Unable to unmarshal json data - Slack integration disabled")
		return
	}
	slackConfig = cfg
	if slackConfig.WebHookURL == "" {
		log.Println("Slack integration disabled due to missing web hook url")
		return
	}
	log.Println("Slack integration enabled")
}

func postMessageToSlack(message string) {
	if slackConfig.WebHookURL == "" {
		return
	}

	msg := &SlackMessage{
		Text: message,
	}

	buffer, err := json.Marshal(msg)
	if err != nil {
		log.Println("Error marshalling slack message", err)
		return
	}

	response, err := http.Post(slackConfig.WebHookURL, "application/json", bytes.NewReader(buffer))
	if err != nil {
		log.Println("Error posting to slack:", err)
		return
	}
	ioutil.ReadAll(response.Body)
}

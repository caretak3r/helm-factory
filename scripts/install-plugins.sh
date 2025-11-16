#!/bin/bash
set -e

# This script installs Jenkins plugins via ConfigMap
# Plugins will be installed on Jenkins startup

PLUGINS=(
    "workflow-aggregator"
    "kubernetes"
    "git"
    "pipeline-stage-view"
    "blueocean"
    "helm"
    "kubernetes-cli"
    "pipeline-utility-steps"
    "yaml"
    "ansicolor"
    "timestamper"
    "build-timeout"
    "credentials-binding"
    "ssh-slaves"
    "matrix-auth"
    "pam-auth"
    "ldap"
    "email-ext"
    "mailer"
    "htmlpublisher"
    "ws-cleanup"
    "ant"
    "gradle"
    "maven-plugin"
    "junit"
    "test-results-analyzer"
    "testng-results"
    "cobertura"
    "jacoco"
    "sonar"
    "checkstyle"
    "findbugs"
    "pmd"
    "warnings"
    "dry"
    "htmlpublisher"
    "claim"
    "copyartifact"
    "envinject"
    "parameterized-trigger"
    "promoted-builds"
    "build-pipeline-plugin"
    "delivery-pipeline-plugin"
    "deploy"
    "deployer-framework"
    "publish-over-ssh"
    "ssh"
    "ssh-agent"
    "ssh-credentials"
    "ssh-steps"
    "ssh-slaves"
    "ssh2easy"
    "ssh-credentials"
    "ssh-agent"
    "ssh-steps"
    "ssh-slaves"
    "ssh2easy"
)

echo "📦 Installing Jenkins plugins..."

# Create plugins list file
PLUGINS_FILE=$(mktemp)
for plugin in "${PLUGINS[@]}"; do
    echo "$plugin" >> "$PLUGINS_FILE"
done

echo "Plugins to install:"
cat "$PLUGINS_FILE"

# Note: In a real setup, you would create a ConfigMap with plugins.txt
# and mount it to /usr/share/jenkins/ref/plugins.txt
# For now, this is informational

echo ""
echo "✅ Plugin list generated"
echo "To install plugins, create a ConfigMap with plugins.txt and mount it to Jenkins"

rm "$PLUGINS_FILE"


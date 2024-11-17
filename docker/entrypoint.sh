#!/usr/bin/env bash
set -e

export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp}"
export WLR_BACKENDS="${WLR_BACKENDS:-headless}"
export WLR_LIBINPUT_NO_DEVICES="${WLR_LIBINPUT_NO_DEVICES:-1}"

# set default configuration values for sway and wayvnc
SWAY_RESOLUTION="${SWAY_RESOLUTION:-1920x1080}"
WAYVNC_PORT="${WAYVNC_PORT:-5910}"
WAYVNC_ENABLE_AUTH="${WAYVNC_ENABLE_AUTH:-false}"
WAYVNC_USERNAME="${WAYVNC_USERNAME:-wayvnc}"
WAYVNC_PASSWORD="${WAYVNC_PASSWORD:-wayvnc}"
WAYVNC_RSA_KEY="${WAYVNC_RSA_KEY:-"/certs/rsa_key.pem"}"
WAYVNC_KEY="${WAYVNC_KEY:-"/certs/key.pem"}"
WAYVNC_CERT="${WAYVNC_CERT:-"/certs/cert.pem"}"

# apply configuration values to sway and wayvnc config files
sed ~/.config/sway/config -i -e "s/\$SWAY_RESOLUTION/$SWAY_RESOLUTION/g"
sed ~/.config/wayvnc/config -i -e "s/\$WAYVNC_PORT/$WAYVNC_PORT/g"
sed ~/.config/wayvnc/config -i -e "s/\$WAYVNC_ENABLE_AUTH/$WAYVNC_ENABLE_AUTH/g"
sed ~/.config/wayvnc/config -i -e "s/\$WAYVNC_USERNAME/$WAYVNC_USERNAME/g"
sed ~/.config/wayvnc/config -i -e "s/\$WAYVNC_PASSWORD/$WAYVNC_PASSWORD/g"
sed ~/.config/wayvnc/config -i -e "s|\$WAYVNC_RSA_KEY|$WAYVNC_RSA_KEY|g"
sed ~/.config/wayvnc/config -i -e "s|\$WAYVNC_KEY|$WAYVNC_KEY|g"
sed ~/.config/wayvnc/config -i -e "s|\$WAYVNC_CERT|$WAYVNC_CERT|g"

# generate SSL certificate for wayvnc if it doesn't already exist
if [ ! -f "$WAYVNC_RSA_KEY" ] || [ ! -f "$WAYVNC_KEY" ] || [ ! -f "$WAYVNC_CERT" ]; then
    echo "Generating wayvnc RSA key..."
    rm -f "$WAYVNC_RSA_KEY"
    ssh-keygen -m pem -f "$WAYVNC_RSA_KEY" -t rsa -N ""
    echo "Generating wayvnc SSL certificate..."
    openssl req -x509 -newkey rsa:4096 -sha256 -days 3650 -nodes \
        -keyout "$WAYVNC_KEY" -out "$WAYVNC_CERT" -subj /CN=localhost \
        -addext subjectAltName=DNS:localhost,DNS:localhost,IP:127.0.0.1
fi

# start wayland session for running browser instances
sway &
sway_pid=$!

# wait for sway to start and get the socket file
echo "Waiting for sway to start..."
retry_count=0
max_retries=5
set +e
while [ -z "$WAYLAND_DISPLAY" ] && [ $retry_count -lt $max_retries ]; do
    sleep 1
    WAYLAND_DISPLAY=$(find "$XDG_RUNTIME_DIR"/wayland-* | head -n 1)
    ((retry_count++))
done
set -e

if [ -z "$WAYLAND_DISPLAY" ]; then
    echo "fatal: Sway not started! (display socket not found in $XDG_RUNTIME_DIR/wayland-*)"
    exit 1
fi
echo "Found WAYLAND_DISPLAY socket: $WAYLAND_DISPLAY"
export WAYLAND_DISPLAY

# start the zendriver app
# note: do not use `uv run` here, as it spawns a new process
.venv/bin/python app/main.py &
app_pid=$!

cleanup() {
    echo "Stopping app..."
    kill -TERM $app_pid 2>/dev/null
    while ps -p $app_pid > /dev/null 2>&1; do sleep 1; done
    echo "Stopping Wayland session..."
    kill $sway_pid 2>/dev/null
    while ps -p $sway_pid > /dev/null 2>&1; do sleep 1; done
    echo "Done."
}

trap cleanup TERM INT

wait $app_pid
wait $sway_pid
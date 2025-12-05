#!/bin/bash

# Check if we are already in a tmux session
if [ -n "$TMUX" ]; then
  echo "Already in a tmux session."
  exit 0
fi

# Start Android emulator in the background
# IMPORTANT: Replace <your_avd_name> with the name of your Android Virtual Device.
# You can list your AVDs with the command: emulator -list-avds
echo "Starting Android emulator in the background..."
emulator -avd <your_avd_name> &

# Name of the tmux session
SESSION_NAME="tsmusic_dev"

# Check if the session already exists
tmux has-session -t $SESSION_NAME 2>/dev/null

if [ $? != 0 ]; then
  echo "Creating new tmux session: $SESSION_NAME"

  # Create a new detached tmux session
  # Window 0: Shell for Gemini/other commands
  tmux new-session -d -s $SESSION_NAME -n "Shell" "bash"

  # Window 1: Neovim
  tmux new-window -t $SESSION_NAME:1 -n "Neovim" "nvim"

  # Select window 0 by default (the "Shell" window)
  tmux select-window -t $SESSION_NAME:0
else
  echo "Attaching to existing tmux session: $SESSION_NAME"
fi

# Attach to the tmux session
tmux attach-session -t $SESSION_NAME

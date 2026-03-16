#!/bin/bash

# ================================================================= #
# Auto Installer & Cloner - TTMediaBot (Custom for kkm2x)
# ================================================================= #

# Check if running as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run this script as root (sudo)."
  exit 1
fi

echo "--- Checking for Git ---"
if ! command -v git &> /dev/null; then
    echo "Git not found. Installing..."
    apt-get update && apt-get install -y git
else
    echo "Git is already installed."
fi

echo "--- Checking for unzip (ZIP extractor) ---"
if ! command -v unzip &> /dev/null; then
    echo "unzip not found. Installing..."
    apt-get install -y unzip
else
    echo "unzip is already installed."
fi

# Define installation path
INSTALL_PATH="/opt/kkm_bot"
REPO_URL="https://github.com/kkm2x/TTMediaBot-Custom"

# Create installation directory if it doesn't exist
if [ -d "$INSTALL_PATH" ]; then
    echo "Installation directory '$INSTALL_PATH' already exists. Updating..."
    cd "$INSTALL_PATH" || exit
    git pull
else
    echo "--- Cloning Repository to $INSTALL_PATH ---"
    git clone "$REPO_URL" "$INSTALL_PATH"
    if [ $? -ne 0 ]; then
        echo "Error cloning repository. Check your internet connection."
        exit 1
    fi
    cd "$INSTALL_PATH" || exit
fi

# Set permissions and ownership
echo "--- Setting Permissions and Ownership ---"
REAL_USER=${SUDO_USER:-$USER}
chown -R "$REAL_USER":"$REAL_USER" "$INSTALL_PATH"
chmod -R 777 "$INSTALL_PATH"
chmod +x "$INSTALL_PATH"/*.sh

# Create global command 'kkm'
echo "--- Creating global command 'kkm' ---"
cat <<EOF > /usr/local/bin/kkm
#!/bin/bash
cd $INSTALL_PATH && sudo ./kkm313.sh
EOF
chmod +x /usr/local/bin/kkm

# Download and extract TeamTalk DLL
echo "========================================="
echo "--- Downloading TeamTalk_DLL.zip ---"
echo "========================================="
DLL_URL="https://github.com/JoaoDEVWHADS/TTMediaBot/releases/download/downloadttdll/TeamTalk_DLL.zip"
DLL_FILE="TeamTalk_DLL.zip"

if [ -f "$DLL_FILE" ]; then
    echo "TeamTalk_DLL.zip already exists. Skipping download."
else
    wget "$DLL_URL" -O "$DLL_FILE"
    if [ $? -ne 0 ]; then
        echo "Error downloading TeamTalk_DLL.zip."
        exit 1
    fi
    echo "Download complete!"
fi

# Extract the ZIP file
echo "========================================="
echo "--- Extracting TeamTalk_DLL.zip ---"
echo "========================================="
unzip -o "$DLL_FILE"
rm -f "$DLL_FILE"
echo "Extraction complete!"

# Final verification
if [ -d "TeamTalk_DLL" ]; then
    echo "✓ Setup Complete!"
    echo "========================================="
    echo "You can now start the bot manager by typing: kkm"
    echo "========================================="
    sleep 2
    exec kkm
else
    echo "ERROR: TeamTalk_DLL folder not found!"
    exit 1
fi

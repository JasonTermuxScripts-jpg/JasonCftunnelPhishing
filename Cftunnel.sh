#!/data/data/com.termux/files/usr/bin/bash

#═══════════════════════════════════════════════════════════════════════════════
#  ☁️  CLOUDFLARE TUNNEL MANAGER v2.0
#  Auteur: Termux Pro Tools
#  Description: Expose localhost sur Internet avec Cloudflare
#═══════════════════════════════════════════════════════════════════════════════

VERSION="2.0"
CONFIG_DIR="$HOME/.cftunnel"
HISTORY_FILE="$CONFIG_DIR/history.log"
FAVORITES_FILE="$CONFIG_DIR/favorites.json"
SETTINGS_FILE="$CONFIG_DIR/settings.json"
PID_FILE="$CONFIG_DIR/tunnel.pid"
LOG_FILE="$CONFIG_DIR/tunnel.log"

# Couleurs
R='\033[0;31m'    # Rouge
G='\033[0;32m'    # Vert
B='\033[0;34m'    # Bleu
C='\033[0;36m'    # Cyan
Y='\033[1;33m'    # Jaune
M='\033[0;35m'    # Magenta
W='\033[1;37m'    # Blanc
D='\033[0;90m'    # Gris
NC='\033[0m'      # Reset
BOLD='\033[1m'

# Emojis
CHECK="✅"
CROSS="❌"
WARN="⚠️"
ROCKET="🚀"
GLOBE="🌐"
LINK="🔗"
FOLDER="📁"
GEAR="⚙️"
CLOUD="☁️"
FIRE="🔥"
STAR="⭐"

#═══════════════════════════════════════════════════════════════════════════════
# INITIALISATION
#═══════════════════════════════════════════════════════════════════════════════

init() {
    mkdir -p "$CONFIG_DIR"
    touch "$HISTORY_FILE"
    
    # Créer settings par défaut
    if [ ! -f "$SETTINGS_FILE" ]; then
        cat > "$SETTINGS_FILE" << 'EOF'
{
    "default_port": 8080,
    "auto_qr": true,
    "auto_copy": true,
    "notifications": true,
    "theme": "cyber",
    "metrics_port": 8081,
    "log_level": "info"
}
EOF
    fi
    
    # Créer favoris par défaut
    if [ ! -f "$FAVORITES_FILE" ]; then
        echo '{"favorites":[]}' > "$FAVORITES_FILE"
    fi
}

#═══════════════════════════════════════════════════════════════════════════════
# INTERFACE GRAPHIQUE
#═══════════════════════════════════════════════════════════════════════════════

banner() {
    clear
    echo -e "${C}"
    if command -v figlet &> /dev/null; then
        figlet -f small "CF Tunnel" 2>/dev/null || echo "CF TUNNEL"
    else
        cat << 'EOF'
   ____ _____   _____                       _ 
  / ___|  ___| |_   _|   _ _ __  _ __   ___| |
 | |   | |_      | || | | | '_ \| '_ \ / _ \ |
 | |___|  _|     | || |_| | | | | | | |  __/ |
  \____|_|       |_| \__,_|_| |_|_| |_|\___|_|
EOF
    fi
    echo -e "${NC}"
    echo -e "${D}══════════════════════════════════════════════════════${NC}"
    echo -e "${W}  ${CLOUD} Cloudflare Tunnel Manager ${C}v${VERSION}${NC}"
    echo -e "${D}══════════════════════════════════════════════════════${NC}"
    echo ""
}

loading() {
    local msg="$1"
    local duration="${2:-3}"
    local chars="⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"
    local end=$((SECONDS + duration))
    
    while [ $SECONDS -lt $end ]; do
        for (( i=0; i<${#chars}; i++ )); do
            echo -en "\r${C}${chars:$i:1}${NC} $msg"
            sleep 0.1
        done
    done
    echo -e "\r${G}${CHECK}${NC} $msg"
}

progress_bar() {
    local current=$1
    local total=$2
    local width=40
    local percent=$((current * 100 / total))
    local filled=$((current * width / total))
    local empty=$((width - filled))
    
    printf "\r${C}[${NC}"
    printf "%${filled}s" | tr ' ' '█'
    printf "%${empty}s" | tr ' ' '░'
    printf "${C}]${NC} ${percent}%%"
}

print_box() {
    local title="$1"
    local content="$2"
    local width=50
    
    echo -e "${C}╔$(printf '═%.0s' $(seq 1 $width))╗${NC}"
    echo -e "${C}║${NC} ${BOLD}$title$(printf ' %.0s' $(seq 1 $((width - ${#title} - 1))))${C}║${NC}"
    echo -e "${C}╠$(printf '═%.0s' $(seq 1 $width))╣${NC}"
    echo -e "${C}║${NC} $content$(printf ' %.0s' $(seq 1 $((width - ${#content} - 1))))${C}║${NC}"
    echo -e "${C}╚$(printf '═%.0s' $(seq 1 $width))╝${NC}"
}

#═══════════════════════════════════════════════════════════════════════════════
# VERIFICATION SYSTEME
#═══════════════════════════════════════════════════════════════════════════════

check_dependencies() {
    echo -e "${Y}${GEAR} Vérification des dépendances...${NC}"
    echo ""
    
    local deps=("cloudflared" "python" "curl" "jq")
    local missing=()
    
    for dep in "${deps[@]}"; do
        if command -v "$dep" &> /dev/null; then
            echo -e "  ${G}${CHECK}${NC} $dep"
        else
            echo -e "  ${R}${CROSS}${NC} $dep"
            missing+=("$dep")
        fi
    done
    
    if [ ${#missing[@]} -gt 0 ]; then
        echo ""
        echo -e "${Y}${WARN} Installation des dépendances manquantes...${NC}"
        pkg install -y "${missing[@]}" 2>/dev/null
    fi
    
    echo ""
}

check_internet() {
    if ping -c 1 cloudflare.com &> /dev/null; then
        return 0
    else
        echo -e "${R}${CROSS} Pas de connexion Internet!${NC}"
        return 1
    fi
}

get_local_ip() {
    ip route get 1 2>/dev/null | awk '{print $NF;exit}' || echo "127.0.0.1"
}

#═══════════════════════════════════════════════════════════════════════════════
# GESTION DES TUNNELS
#═══════════════════════════════════════════════════════════════════════════════

quick_tunnel() {
    banner
    echo -e "${ROCKET} ${BOLD}QUICK TUNNEL${NC}"
    echo -e "${D}Crée un tunnel temporaire instantanément${NC}"
    echo ""
    
    # Lecture du port
    local default_port=$(jq -r '.default_port' "$SETTINGS_FILE" 2>/dev/null || echo "8080")
    read -p "$(echo -e "${C}➤${NC} Port local [${default_port}]: ")" port
    port=${port:-$default_port}
    
    # Vérifier si le port est utilisé
    if ! check_port "$port"; then
        echo ""
        echo -e "${Y}${WARN} Aucun service sur le port $port${NC}"
        echo -e "Veux-tu démarrer un serveur web?"
        echo ""
        echo "  1) Serveur Python (fichiers statiques)"
        echo "  2) Serveur PHP"
        echo "  3) Serveur Node.js"
        echo "  4) Non, je vais démarrer mon propre serveur"
        echo ""
        read -p "$(echo -e "${C}➤${NC} Choix [1-4]: ")" srv_choice
        
        case $srv_choice in
            1) start_python_server "$port" ;;
            2) start_php_server "$port" ;;
            3) start_node_server "$port" ;;
            4) 
                echo -e "${Y}${WARN} Démarre ton serveur sur le port $port puis relance${NC}"
                read -p "Appuie sur Entrée quand c'est prêt..."
                ;;
        esac
    fi
    
    echo ""
    echo -e "${G}${ROCKET} Création du tunnel...${NC}"
    echo -e "${D}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    # Lancer cloudflared et capturer l'URL
    cloudflared tunnel --url "http://localhost:$port" 2>&1 | tee "$LOG_FILE" | while read line; do
        # Extraire l'URL
        if [[ "$line" == *"trycloudflare.com"* ]]; then
            url=$(echo "$line" | grep -oP 'https://[a-zA-Z0-9-]+\.trycloudflare\.com')
            if [ -n "$url" ]; then
                echo ""
                echo -e "${D}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
                echo ""
                echo -e "${G}${CHECK} TUNNEL ACTIF!${NC}"
                echo ""
                echo -e "${LINK} ${BOLD}URL Publique:${NC}"
                echo -e "   ${C}$url${NC}"
                echo ""
                
                # Générer QR Code
                if command -v qrencode &> /dev/null; then
                    echo -e "${GLOBE} ${BOLD}QR Code:${NC}"
                    qrencode -t ANSIUTF8 "$url" 2>/dev/null
                fi
                
                # Sauvegarder dans l'historique
                echo "$(date '+%Y-%m-%d %H:%M:%S')|$port|$url" >> "$HISTORY_FILE"
                
                # Copier dans le presse-papier si disponible
                if command -v termux-clipboard-set &> /dev/null; then
                    echo "$url" | termux-clipboard-set
                    echo -e "${G}${CHECK} URL copiée dans le presse-papier${NC}"
                fi
                
                echo ""
                echo -e "${Y}Appuie sur Ctrl+C pour arrêter le tunnel${NC}"
            fi
        else
            echo -e "${D}$line${NC}"
        fi
    done
}

advanced_tunnel() {
    banner
    echo -e "${FIRE} ${BOLD}TUNNEL AVANCÉ${NC}"
    echo ""
    
    echo "  1) Tunnel HTTP simple"
    echo "  2) Tunnel avec métriques"
    echo "  3) Tunnel multi-services"
    echo "  4) Tunnel avec rate limiting"
    echo "  5) Tunnel avec access control"
    echo ""
    read -p "$(echo -e "${C}➤${NC} Choix: ")" adv_choice
    
    case $adv_choice in
        1)
            read -p "Port: " port
            cloudflared tunnel --url "http://localhost:$port"
            ;;
        2)
            read -p "Port service: " port
            read -p "Port métriques [8081]: " metrics
            metrics=${metrics:-8081}
            echo -e "${G}[+] Métriques disponibles sur http://localhost:$metrics/metrics${NC}"
            cloudflared tunnel --url "http://localhost:$port" --metrics "localhost:$metrics"
            ;;
        3)
            multi_service_tunnel
            ;;
        4)
            read -p "Port: " port
            read -p "Requêtes/seconde max [100]: " rps
            rps=${rps:-100}
            cloudflared tunnel --url "http://localhost:$port" --proxy-keepalive-timeout 90s
            ;;
        5)
            authenticated_tunnel
            ;;
    esac
}

multi_service_tunnel() {
    banner
    echo -e "${STAR} ${BOLD}TUNNEL MULTI-SERVICES${NC}"
    echo ""
    
    read -p "Nombre de services: " count
    
    local config_file="/tmp/cf-config-$$.yml"
    
    cat > "$config_file" << EOF
tunnel: multi-service
ingress:
EOF
    
    for ((i=1; i<=count; i++)); do
        echo ""
        echo -e "${C}Service $i:${NC}"
        read -p "  Path (ex: /api, /app): " path
        read -p "  Port local: " port
        
        cat >> "$config_file" << EOF
  - hostname: "*"
    path: $path
    service: http://localhost:$port
EOF
    done
    
    # Ajouter le catch-all
    cat >> "$config_file" << EOF
  - service: http_status:404
EOF
    
    echo ""
    echo -e "${G}[+] Configuration créée${NC}"
    echo ""
    cat "$config_file"
    echo ""
    
    cloudflared tunnel --config "$config_file" run
}

authenticated_tunnel() {
    banner
    echo -e "${GEAR} ${BOLD}TUNNEL AVEC AUTHENTIFICATION${NC}"
    echo ""
    
    # Vérifier si déjà authentifié
    if [ ! -f "$HOME/.cloudflared/cert.pem" ]; then
        echo -e "${Y}${WARN} Tu dois d'abord te connecter à Cloudflare${NC}"
        echo ""
        read -p "Continuer avec l'authentification? (o/n): " auth
        if [[ "$auth" == "o" ]]; then
            cloudflared tunnel login
        else
            return
        fi
    fi
    
    echo ""
    echo "  1) Créer un nouveau tunnel permanent"
    echo "  2) Lister mes tunnels"
    echo "  3) Supprimer un tunnel"
    echo "  4) Lancer un tunnel existant"
    echo ""
    read -p "$(echo -e "${C}➤${NC} Choix: ")" auth_choice
    
    case $auth_choice in
        1)
            read -p "Nom du tunnel: " tunnel_name
            cloudflared tunnel create "$tunnel_name"
            echo ""
            echo -e "${G}${CHECK} Tunnel '$tunnel_name' créé!${NC}"
            
            read -p "Configurer un hostname? (o/n): " config_host
            if [[ "$config_host" == "o" ]]; then
                read -p "Hostname (ex: app.mondomaine.com): " hostname
                read -p "Port local: " port
                
                cloudflared tunnel route dns "$tunnel_name" "$hostname"
                
                # Créer config
                cat > "$HOME/.cloudflared/$tunnel_name.yml" << EOF
tunnel: $tunnel_name
credentials-file: $HOME/.cloudflared/${tunnel_name}.json
ingress:
  - hostname: $hostname
    service: http://localhost:$port
  - service: http_status:404
EOF
                echo -e "${G}${CHECK} Configuration sauvegardée${NC}"
            fi
            ;;
        2)
            echo ""
            cloudflared tunnel list
            ;;
        3)
            cloudflared tunnel list
            echo ""
            read -p "Nom du tunnel à supprimer: " del_name
            cloudflared tunnel delete "$del_name"
            ;;
        4)
            cloudflared tunnel list
            echo ""
            read -p "Nom du tunnel à lancer: " run_name
            if [ -f "$HOME/.cloudflared/$run_name.yml" ]; then
                cloudflared tunnel --config "$HOME/.cloudflared/$run_name.yml" run
            else
                cloudflared tunnel run "$run_name"
            fi
            ;;
    esac
}

#═══════════════════════════════════════════════════════════════════════════════
# SERVEURS WEB
#═══════════════════════════════════════════════════════════════════════════════

check_port() {
    local port=$1
    if command -v ss &> /dev/null; then
        ss -tuln | grep -q ":$port "
    elif command -v netstat &> /dev/null; then
        netstat -tuln | grep -q ":$port "
    else
        # Essayer de se connecter
        (echo > /dev/tcp/localhost/$port) 2>/dev/null
    fi
}

start_python_server() {
    local port=$1
    read -p "Dossier à servir [$PWD]: " dir
    dir=${dir:-$PWD}
    
    echo -e "${G}[+] Démarrage serveur Python sur :$port${NC}"
    cd "$dir"
    python -m http.server "$port" &
    echo $! > "$PID_FILE.server"
    sleep 1
}

start_php_server() {
    local port=$1
    read -p "Dossier à servir [$PWD]: " dir
    dir=${dir:-$PWD}
    
    echo -e "${G}[+] Démarrage serveur PHP sur :$port${NC}"
    cd "$dir"
    php -S "0.0.0.0:$port" &
    echo $! > "$PID_FILE.server"
    sleep 1
}

start_node_server() {
    local port=$1
    read -p "Dossier à servir [$PWD]: " dir
    dir=${dir:-$PWD}
    
    # Créer serveur express simple
    local server_file="/tmp/node-server-$$.js"
    cat > "$server_file" << 'NODEJS'
const http = require('http');
const fs = require('fs');
const path = require('path');

const port = process.argv[2] || 8080;
const dir = process.argv[3] || '.';

const mimeTypes = {
    '.html': 'text/html',
    '.css': 'text/css',
    '.js': 'application/javascript',
    '.json': 'application/json',
    '.png': 'image/png',
    '.jpg': 'image/jpeg',
    '.gif': 'image/gif',
    '.svg': 'image/svg+xml',
    '.ico': 'image/x-icon'
};

const server = http.createServer((req, res) => {
    let filePath = path.join(dir, req.url === '/' ? 'index.html' : req.url);
    const ext = path.extname(filePath);
    const contentType = mimeTypes[ext] || 'application/octet-stream';
    
    fs.readFile(filePath, (err, data) => {
        if (err) {
            if (err.code === 'ENOENT') {
                res.writeHead(404, {'Content-Type': 'text/html'});
                res.end('<h1>404 - Not Found</h1>');
            } else {
                res.writeHead(500);
                res.end('Server Error');
            }
        } else {
            res.writeHead(200, {'Content-Type': contentType});
            res.end(data);
        }
    });
});

server.listen(port, () => {
    console.log(`🚀 Server running at http://localhost:${port}/`);
});
NODEJS
    
    echo -e "${G}[+] Démarrage serveur Node.js sur :$port${NC}"
    node "$server_file" "$port" "$dir" &
    echo $! > "$PID_FILE.server"
    sleep 1
}

#═══════════════════════════════════════════════════════════════════════════════
# PARTAGE DE FICHIERS
#═══════════════════════════════════════════════════════════════════════════════

share_file() {
    banner
    echo -e "${FOLDER} ${BOLD}PARTAGE DE FICHIERS${NC}"
    echo ""
    
    echo "  1) Partager un fichier"
    echo "  2) Partager un dossier"
    echo "  3) Partager avec upload (recevoir des fichiers)"
    echo ""
    read -p "$(echo -e "${C}➤${NC} Choix: ")" share_choice
    
    case $share_choice in
        1)
            read -p "Chemin du fichier: " filepath
            if [ ! -f "$filepath" ]; then
                echo -e "${R}${CROSS} Fichier non trouvé!${NC}"
                return
            fi
            
            # Créer dossier temporaire
            local tmpdir=$(mktemp -d)
            cp "$filepath" "$tmpdir/"
            local filename=$(basename "$filepath")
            
            echo ""
            echo -e "${G}[+] Partage de: $filename${NC}"
            
            cd "$tmpdir"
            python -m http.server 9876 &
            local pid=$!
            sleep 1
            
            echo ""
            cloudflared tunnel --url http://localhost:9876 2>&1 | while read line; do
                if [[ "$line" == *"trycloudflare.com"* ]]; then
                    url=$(echo "$line" | grep -oP 'https://[a-zA-Z0-9-]+\.trycloudflare\.com')
                    if [ -n "$url" ]; then
                        echo ""
                        echo -e "${G}${CHECK} Fichier accessible à:${NC}"
                        echo -e "   ${C}${url}/${filename}${NC}"
                        echo ""
                        if command -v qrencode &> /dev/null; then
                            qrencode -t ANSIUTF8 "${url}/${filename}"
                        fi
                    fi
                fi
            done
            
            kill $pid 2>/dev/null
            rm -rf "$tmpdir"
            ;;
        2)
            read -p "Chemin du dossier: " dirpath
            if [ ! -d "$dirpath" ]; then
                echo -e "${R}${CROSS} Dossier non trouvé!${NC}"
                return
            fi
            
            cd "$dirpath"
            python -m http.server 9876 &
            local pid=$!
            sleep 1
            
            cloudflared tunnel --url http://localhost:9876
            kill $pid 2>/dev/null
            ;;
        3)
            upload_server
            ;;
    esac
}

upload_server() {
    local port=9877
    local upload_dir="$HOME/uploads"
    mkdir -p "$upload_dir"
    
    # Créer serveur d'upload Python
    local server_file="/tmp/upload-server-$$.py"
    cat > "$server_file" << 'PYTHON'
#!/usr/bin/env python3
import http.server
import cgi
import os
import sys

class UploadHandler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/':
            self.send_response(200)
            self.send_header('Content-type', 'text/html')
            self.end_headers()
            html = '''
<!DOCTYPE html>
<html>
<head>
    <title>📤 File Upload</title>
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            display: flex;
            justify-content: center;
            align-items: center;
            margin: 0;
        }
        .container {
            background: white;
            padding: 40px;
            border-radius: 20px;
            box-shadow: 0 20px 60px rgba(0,0,0,0.3);
            text-align: center;
            max-width: 400px;
            width: 90%;
        }
        h1 { color: #333; margin-bottom: 30px; }
        .upload-area {
            border: 3px dashed #667eea;
            border-radius: 15px;
            padding: 40px;
            margin: 20px 0;
            transition: all 0.3s;
            cursor: pointer;
        }
        .upload-area:hover {
            background: #f0f0ff;
            border-color: #764ba2;
        }
        input[type="file"] { display: none; }
        .btn {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            border: none;
            padding: 15px 40px;
            border-radius: 30px;
            font-size: 16px;
            cursor: pointer;
            transition: transform 0.2s;
        }
        .btn:hover { transform: scale(1.05); }
        #fileName { margin: 10px 0; color: #666; }
    </style>
</head>
<body>
    <div class="container">
        <h1>📤 Upload File</h1>
        <form action="/upload" method="POST" enctype="multipart/form-data">
            <label class="upload-area" id="dropArea">
                <input type="file" name="file" id="fileInput" required>
                <p>📁 Click or drag file here</p>
            </label>
            <p id="fileName"></p>
            <button type="submit" class="btn">🚀 Upload</button>
        </form>
    </div>
    <script>
        document.getElementById('fileInput').onchange = function() {
            document.getElementById('fileName').textContent = this.files[0].name;
        };
    </script>
</body>
</html>
            '''
            self.wfile.write(html.encode())
        else:
            super().do_GET()
    
    def do_POST(self):
        if self.path == '/upload':
            form = cgi.FieldStorage(
                fp=self.rfile,
                headers=self.headers,
                environ={'REQUEST_METHOD': 'POST'}
            )
            
            if 'file' in form:
                file_item = form['file']
                filename = os.path.basename(file_item.filename)
                upload_dir = sys.argv[2] if len(sys.argv) > 2 else '.'
                filepath = os.path.join(upload_dir, filename)
                
                with open(filepath, 'wb') as f:
                    f.write(file_item.file.read())
                
                self.send_response(200)
                self.send_header('Content-type', 'text/html')
                self.end_headers()
                html = f'''
<!DOCTYPE html>
<html>
<head>
    <title>✅ Upload Success</title>
    <style>
        body {{
            font-family: sans-serif;
            background: linear-gradient(135deg, #11998e 0%, #38ef7d 100%);
            min-height: 100vh;
            display: flex;
            justify-content: center;
            align-items: center;
        }}
        .container {{
            background: white;
            padding: 40px;
            border-radius: 20px;
            text-align: center;
        }}
    </style>
</head>
<body>
    <div class="container">
        <h1>✅ Success!</h1>
        <p>File uploaded: <strong>{filename}</strong></p>
        <a href="/">← Upload another</a>
    </div>
</body>
</html>
                '''
                self.wfile.write(html.encode())
                print(f'📥 Received: {filename}')

if __name__ == '__main__':
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8080
    server = http.server.HTTPServer(('', port), UploadHandler)
    print(f'🚀 Upload server running on port {port}')
    server.serve_forever()
PYTHON
    
    echo -e "${G}[+] Démarrage serveur d'upload...${NC}"
    echo -e "${D}Les fichiers seront sauvegardés dans: $upload_dir${NC}"
    echo ""
    
    python "$server_file" "$port" "$upload_dir" &
    local pid=$!
    sleep 1
    
    cloudflared tunnel --url "http://localhost:$port"
    kill $pid 2>/dev/null
}

#═══════════════════════════════════════════════════════════════════════════════
# SSH TUNNEL
#═══════════════════════════════════════════════════════════════════════════════

ssh_tunnel() {
    banner
    echo -e "${GEAR} ${BOLD}SSH TUNNEL${NC}"
    echo -e "${D}Accède à ton téléphone via SSH depuis n'importe où${NC}"
    echo ""
    
    # Vérifier/démarrer sshd
    if ! pgrep -x "sshd" > /dev/null; then
        echo -e "${Y}[+] Démarrage du serveur SSH...${NC}"
        sshd
    fi
    
    local ssh_port=$(grep -E "^Port" "$PREFIX/etc/ssh/sshd_config" 2>/dev/null | awk '{print $2}')
    ssh_port=${ssh_port:-8022}
    
    echo -e "${G}${CHECK} SSH actif sur le port $ssh_port${NC}"
    echo ""
    echo -e "${D}Pour te connecter, utilise:${NC}"
    echo -e "  ssh -p <PORT> $(whoami)@<URL>"
    echo ""
    
    cloudflared tunnel --url "tcp://localhost:$ssh_port" 2>&1 | while read line; do
        echo "$line"
        if [[ "$line" == *"tcp://"* ]]; then
            url=$(echo "$line" | grep -oP 'tcp://[a-zA-Z0-9.-]+:[0-9]+')
            if [ -n "$url" ]; then
                host=$(echo "$url" | sed 's|tcp://||' | cut -d: -f1)
                port=$(echo "$url" | sed 's|tcp://||' | cut -d: -f2)
                echo ""
                echo -e "${G}${CHECK} Connexion SSH:${NC}"
                echo -e "   ${C}ssh -p $port $(whoami)@$host${NC}"
                echo ""
            fi
        fi
    done
}

#═══════════════════════════════════════════════════════════════════════════════
# MONITORING & LOGS
#═══════════════════════════════════════════════════════════════════════════════

show_dashboard() {
    while true; do
        clear
        echo -e "${C}╔════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${C}║${NC}              ${BOLD}📊 TUNNEL DASHBOARD${NC}                          ${C}║${NC}"
        echo -e "${C}╚════════════════════════════════════════════════════════════╝${NC}"
        echo ""
        
        # Status système
        echo -e "${Y}📱 SYSTÈME${NC}"
        echo -e "   CPU: $(top -bn1 | grep "Cpu(s)" | awk '{print $2}' 2>/dev/null || echo "N/A")%"
        echo -e "   RAM: $(free -m 2>/dev/null | awk 'NR==2{printf "%.1f%%", $3*100/$2 }' || echo "N/A")"
        echo -e "   IP: $(get_local_ip)"
        echo ""
        
        # Tunnels actifs
        echo -e "${Y}🔗 TUNNELS ACTIFS${NC}"
        if pgrep -x "cloudflared" > /dev/null; then
            pgrep -ax "cloudflared" | while read pid cmd; do
                echo -e "   ${G}●${NC} PID: $pid"
            done
        else
            echo -e "   ${D}Aucun tunnel actif${NC}"
        fi
        echo ""
        
        # Historique récent
        echo -e "${Y}📜 HISTORIQUE RÉCENT${NC}"
        tail -5 "$HISTORY_FILE" 2>/dev/null | while read line; do
            echo -e "   ${D}$line${NC}"
        done
        echo ""
        
        echo -e "${D}Rafraîchissement toutes les 5s | Ctrl+C pour quitter${NC}"
        sleep 5
    done
}

show_history() {
    banner
    echo -e "${STAR} ${BOLD}HISTORIQUE DES TUNNELS${NC}"
    echo ""
    
    if [ -f "$HISTORY_FILE" ] && [ -s "$HISTORY_FILE" ]; then
        echo -e "${D}Date                  | Port  | URL${NC}"
        echo -e "${D}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        tail -20 "$HISTORY_FILE" | while IFS='|' read date port url; do
            echo -e "${W}$date${NC} | ${C}$port${NC} | ${G}$url${NC}"
        done
    else
        echo -e "${D}Aucun historique${NC}"
    fi
    
    echo ""
    read -p "Appuie sur Entrée pour continuer..."
}

view_logs() {
    banner
    echo -e "${GEAR} ${BOLD}LOGS EN TEMPS RÉEL${NC}"
    echo ""
    
    if [ -f "$LOG_FILE" ]; then
        tail -f "$LOG_FILE"
    else
        echo -e "${D}Aucun log disponible${NC}"
        read -p "Appuie sur Entrée..."
    fi
}

#═══════════════════════════════════════════════════════════════════════════════
# PARAMÈTRES
#═══════════════════════════════════════════════════════════════════════════════

settings_menu() {
    while true; do
        banner
        echo -e "${GEAR} ${BOLD}PARAMÈTRES${NC}"
        echo ""
        
        # Charger settings actuels
        local default_port=$(jq -r '.default_port' "$SETTINGS_FILE" 2>/dev/null)
        local auto_qr=$(jq -r '.auto_qr' "$SETTINGS_FILE" 2>/dev/null)
        local notifications=$(jq -r '.notifications' "$SETTINGS_FILE" 2>/dev/null)
        
        echo "  1) Port par défaut: ${C}$default_port${NC}"
        echo "  2) QR Code auto: ${C}$auto_qr${NC}"
        echo "  3) Notifications: ${C}$notifications${NC}"
        echo "  4) Réinitialiser les paramètres"
        echo "  5) Effacer l'historique"
        echo "  6) Retour"
        echo ""
        read -p "$(echo -e "${C}➤${NC} Choix: ")" set_choice
        
        case $set_choice in
            1)
                read -p "Nouveau port par défaut: " new_port
                jq ".default_port = $new_port" "$SETTINGS_FILE" > /tmp/settings.tmp
                mv /tmp/settings.tmp "$SETTINGS_FILE"
                echo -e "${G}${CHECK} Port mis à jour${NC}"
                sleep 1
                ;;
            2)
                if [ "$auto_qr" == "true" ]; then
                    jq '.auto_qr = false' "$SETTINGS_FILE" > /tmp/settings.tmp
                else
                    jq '.auto_qr = true' "$SETTINGS_FILE" > /tmp/settings.tmp
                fi
                mv /tmp/settings.tmp "$SETTINGS_FILE"
                ;;
            3)
                if [ "$notifications" == "true" ]; then
                    jq '.notifications = false' "$SETTINGS_FILE" > /tmp/settings.tmp
                else
                    jq '.notifications = true' "$SETTINGS_FILE" > /tmp/settings.tmp
                fi
                mv /tmp/settings.tmp "$SETTINGS_FILE"
                ;;
            4)
                rm -f "$SETTINGS_FILE"
                init
                echo -e "${G}${CHECK} Paramètres réinitialisés${NC}"
                sleep 1
                ;;
            5)
                rm -f "$HISTORY_FILE"
                touch "$HISTORY_FILE"
                echo -e "${G}${CHECK} Historique effacé${NC}"
                sleep 1
                ;;
            6) return ;;
        esac
    done
}

#═══════════════════════════════════════════════════════════════════════════════
# AIDE
#═══════════════════════════════════════════════════════════════════════════════

show_help() {
    banner
    echo -e "${BOLD}📖 AIDE & DOCUMENTATION${NC}"
    echo ""
    echo -e "${Y}Qu'est-ce que c'est?${NC}"
    echo "  Ce script permet d'exposer un serveur local sur Internet"
    echo "  en utilisant Cloudflare Tunnel (gratuit et sécurisé)."
    echo ""
    echo -e "${Y}Comment ça marche?${NC}"
    echo "  1. Démarre un serveur web sur un port (ex: 8080)"
    echo "  2. Lance un tunnel vers ce port"
    echo "  3. Cloudflare te donne une URL publique"
    echo "  4. N'importe qui peut accéder à ton serveur via cette URL"
    echo ""
    echo -e "${Y}Cas d'utilisation:${NC}"
    echo "  • Partager des fichiers rapidement"
    echo "  • Tester une app web sur différents appareils"
    echo "  • Accès SSH à ton téléphone depuis n'importe où"
    echo "  • Démonstrations de projets"
    echo "  • Webhooks pour le développement"
    echo ""
    echo -e "${Y}Avantages de Cloudflare:${NC}"
    echo "  ✓ 100% gratuit"
    echo "  ✓ Chiffrement HTTPS automatique"
    echo "  ✓ Pas besoin de compte pour les tunnels temporaires"
    echo "  ✓ Protection DDoS incluse"
    echo "  ✓ Très rapide"
    echo ""
    read -p "Appuie sur Entrée pour continuer..."
}

#═══════════════════════════════════════════════════════════════════════════════
# MENU PRINCIPAL
#═══════════════════════════════════════════════════════════════════════════════

main_menu() {
    while true; do
        banner
        
        echo -e "${BOLD}MENU PRINCIPAL${NC}"
        echo ""
        echo -e "  ${C}1)${NC} ${ROCKET} Quick Tunnel          ${D}(temporaire, instantané)${NC}"
        echo -e "  ${C}2)${NC} ${FIRE} Tunnel Avancé          ${D}(options avancées)${NC}"
        echo -e "  ${C}3)${NC} ${FOLDER} Partage de fichiers    ${D}(fichiers, dossiers, upload)${NC}"
        echo -e "  ${C}4)${NC} ${GEAR} SSH Tunnel             ${D}(accès distant au téléphone)${NC}"
        echo -e "  ${C}5)${NC} ${STAR} Tunnels Permanents     ${D}(avec compte Cloudflare)${NC}"
        echo ""
        echo -e "  ${D}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo ""
        echo -e "  ${C}6)${NC} 📊 Dashboard             ${D}(monitoring en temps réel)${NC}"
        echo -e "  ${C}7)${NC} 📜 Historique            ${D}(tunnels précédents)${NC}"
        echo -e "  ${C}8)${NC} ⚙️  Paramètres"
        echo -e "  ${C}9)${NC} 📖 Aide"
        echo -e "  ${C}0)${NC} 🚪 Quitter"
        echo ""
        read -p "$(echo -e "${C}➤${NC} Choix: ")" choice
        
        case $choice in
            1) quick_tunnel ;;
            2) advanced_tunnel ;;
            3) share_file ;;
            4) ssh_tunnel ;;
            5) authenticated_tunnel ;;
            6) show_dashboard ;;
            7) show_history ;;
            8) settings_menu ;;
            9) show_help ;;
            0)
                echo ""
                echo -e "${G}👋 À bientôt!${NC}"
                # Nettoyer
                if [ -f "$PID_FILE.server" ]; then
                    kill $(cat "$PID_FILE.server") 2>/dev/null
                    rm "$PID_FILE.server"
                fi
                exit 0
                ;;
            *)
                echo -e "${R}${CROSS} Choix invalide${NC}"
                sleep 1
                ;;
        esac
    done
}

#═══════════════════════════════════════════════════════════════════════════════
# POINT D'ENTRÉE
#═══════════════════════════════════════════════════════════════════════════════

# Gestion des arguments CLI
if [ "$1" ]; then
    case $1 in
        -q|--quick)
            port=${2:-8080}
            cloudflared tunnel --url "http://localhost:$port"
            ;;
        -s|--share)
            shift
            filepath="$1"
            if [ -f "$filepath" ]; then
                tmpdir=$(mktemp -d)
                cp "$filepath" "$tmpdir/"
                cd "$tmpdir"
                python -m http.server 9876 &
                pid=$!
                sleep 1
                cloudflared tunnel --url http://localhost:9876
                kill $pid 2>/dev/null
            else
                echo "Fichier non trouvé: $filepath"
            fi
            ;;
        -h|--help)
            echo "Usage: cftunnel.sh [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  -q, --quick [PORT]    Quick tunnel sur le port spécifié"
            echo "  -s, --share FILE      Partager un fichier"
            echo "  -h, --help            Afficher cette aide"
            echo ""
            echo "Sans arguments, lance le menu interactif."
            ;;
        *)
            echo "Option inconnue: $1"
            echo "Utilise -h pour l'aide"
            ;;
    esac
else
    # Mode interactif
    init
    check_dependencies
    main_menu
fi

#!/bin/bash

# الكشف التلقائي عن موقع السكربت وتعيين المسارات ديناميكياً
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOTS_ROOT="${SCRIPT_DIR}/bots"
CONFIG_SOURCE="config.json"

# الإعدادات
BOT_IMAGE="ttmediabot"

# التحقق من الصلاحيات (root)
if [ "$EUID" -ne 0 ]; then
  echo "يرجى تشغيل هذا السكربت بصلاحيات الجذر (sudo)."
  exit 1
fi

# الألوان
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # لا يوجد لون

# وظيفة: عرض الترويسة
header() {
    clear
    echo -e "${GREEN}=========================================${NC}"
    echo -e "${GREEN}      مدير بوتات TTMediaBot (Docker)     ${NC}"
    echo -e "${GREEN}=========================================${NC}"
    echo ""
}

# وظيفة: تثبيت التبعيات
install_dependencies() {
    header
    echo -e "${YELLOW}جاري التحقق من التبعيات...${NC}"

    if ! command -v docker &> /dev/null; then
        echo "Docker غير موجود. جاري التثبيت من المستودع الرسمي..."
        
        apt-get update
        apt-get install -y ca-certificates curl gnupg lsb-release

        mkdir -p /etc/apt/keyrings
        rm -f /etc/apt/keyrings/docker.gpg
        curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        chmod a+r /etc/apt/keyrings/docker.gpg

        echo \
          "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \
          $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

        apt-get update
        apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

        systemctl enable --now docker
        
        REAL_USER=${SUDO_USER:-$USER}
        if [ "$REAL_USER" != "root" ]; then
            usermod -aG docker "$REAL_USER"
            echo "تمت إضافة المستخدم '$REAL_USER' إلى مجموعة docker."
        fi
    else
        echo -e "${GREEN}Docker مثبت بالفعل.${NC}"
    fi

    if ! command -v jq &> /dev/null; then
        echo "jq غير موجود. جاري التثبيت..."
        apt-get install -y jq
    else
        echo -e "${GREEN}jq مثبت بالفعل.${NC}"
    fi
    sleep 1
}

# وظيفة: إعادة إنشاء حاويات البوت
recreate_bot_containers() {
    echo -e "${YELLOW}جاري إعادة إنشاء الحاويات بالصورة الجديدة...${NC}"
    
    if [ ! -d "$BOTS_ROOT" ]; then return; fi
    
    for d in "$BOTS_ROOT"/*; do
        if [ -d "$d" ]; then
            bot_name=$(basename "$d")
            
            if [ "$(docker ps -a -q -f name=^/${bot_name}$)" ]; then
                docker rm -f "$bot_name" >/dev/null 2>&1
            fi
            
            if [ ! -f "$d/cookies.txt" ]; then touch "$d/cookies.txt"; fi
            
            docker create \
                --name "${bot_name}" \
                --network host \
                --label "role=ttmediabot" \
                --restart always \
                -v "${d}:/home/ttbot/TTMediaBot/data" \
                -v "${d}/cookies.txt:/home/ttbot/TTMediaBot/data/cookies.txt" \
                "${BOT_IMAGE}" > /dev/null 2>&1
                
            if [ $? -eq 0 ]; then
                echo "  ✓ تم تحديث الحاوية '$bot_name'"
            else
                echo "  ✗ خطأ في تحديث '$bot_name'"
            fi
        fi
    done
}

# وظيفة: بناء صورة Docker
build_image() {
    header
    echo -e "${YELLOW}جاري التحقق من صورة Docker '${BOT_IMAGE}'...${NC}"
    
    if [ ! -f "Dockerfile" ]; then
        echo -e "${RED}خطأ: ملف Dockerfile غير موجود في المجلد الحالي!${NC}"
        exit 1
    fi

    if [[ "$(docker images -q ${BOT_IMAGE} 2> /dev/null)" == "" ]]; then
        echo "الصورة غير موجودة. جاري بناء الصورة..."
        docker build --build-arg CACHEBUST=$(date +%s) -t ${BOT_IMAGE} .
        if [ $? -eq 0 ]; then
             echo -e "${GREEN}تم بناء الصورة بنجاح!${NC}"
        else
             echo -e "${RED}خطأ في بناء الصورة! تحقق من Dockerfile.${NC}"
             exit 1
        fi
        sleep 1
    else
        echo -e "${GREEN}الصورة '${BOT_IMAGE}' موجودة بالفعل.${NC}"
        sleep 1
    fi
}

# وظيفة: إنشاء بوت جديد
create_bot() {
    header
    echo -e "${YELLOW} --- إنشاء بوت جديد --- ${NC}"
    
    if [ ! -f "$CONFIG_SOURCE" ]; then
       echo -e "${RED}خطأ: الملف '$CONFIG_SOURCE' غير موجود.${NC}"
       return
    fi
    
    read -p "اسم البوت (سيكون اسم المجلد والحاوية): " bot_name
    if [[ -z "$bot_name" ]]; then echo -e "${RED}اسم غير صالح.${NC}"; sleep 2; return; fi
    
    BOT_DIR="${BOTS_ROOT}/${bot_name}"
    
    if [ "$(docker ps -a -q -f name=^/${bot_name}$)" ]; then
        echo -e "${RED}خطأ: توجد حاوية بهذا الاسم بالفعل.${NC}"
        sleep 2
        return
    fi
    
    if [ -d "$BOT_DIR" ]; then
        echo -e "${RED}يوجد مجلد لهذا البوت بالفعل!${NC}"
        sleep 2
        return
    fi

    read -p "عنوان سيرفر TeamTalk: " server_addr
    read -p "منفذ TCP (الافتراضي 10333): " tcp_port
    tcp_port=${tcp_port:-10333}
    read -p "منفذ UDP (الافتراضي 10333): " udp_port
    udp_port=${udp_port:-10333}
    
    echo "هل الاتصال مشفر؟"
    echo "1. لا (False)"
    echo "2. نعم (True)"
    read -p "الخيار: " encrypted_opt
    if [ "$encrypted_opt" == "2" ]; then encrypted="true"; else encrypted="false"; fi
    
    read -p "اسم المستخدم: " username
    read -sp "كلمة المرور: " password
    echo ""
    read -p "لقب البوت (الافتراضي: TTMediaBot): " nickname
    nickname=${nickname:-TTMediaBot}
    
    echo "--- إعداد الكوكيز ---"
    echo "1. لصق محتوى الكوكيز مباشرة (موصى به)"
    echo "2. تقديم مسار لملف cookies.txt"
    read -p "الخيار (1/2): " cookies_opt
    
    if [ "$cookies_opt" == "1" ]; then
        echo "يرجى لصق محتوى الكوكيز أدناه."
        echo "سيتم الحفظ تلقائياً بعد ثانية واحدة من انتهاء اللصق وضغط Enter."
        cookies_path="/tmp/temp_cookies.txt"
        > "$cookies_path"
        while IFS= read -t 1 -r line; do
            echo "$line" >> "$cookies_path"
        done
    else
        read -p "المسار الكامل لملف الكوكيز (مثال: /root/cookies.txt): " cookies_path
    fi
    
    read -p "القناة (الافتراضي: /): " channel
    channel=${channel:-/}
    read -sp "كلمة مرور القناة (الافتراضي: فارغ): " channel_password
    echo ""

    echo -e "${YELLOW}جاري إنشاء البوت...${NC}"
    mkdir -p "$BOT_DIR"
    cp "$CONFIG_SOURCE" "$BOT_DIR/config.json"
    
    if [ -f "$cookies_path" ]; then
        cp "$cookies_path" "$BOT_DIR/cookies.txt"
    else
        touch "$BOT_DIR/cookies.txt"
    fi
    
    tmp_config=$(mktemp)
    jq --arg host "$server_addr" \
       --argjson tcp "$tcp_port" \
       --argjson udp "$udp_port" \
       --argjson enc "$encrypted" \
       --arg nick "$nickname" \
       --arg user "$username" \
       --arg pass "$password" \
       --arg chan "$channel" \
       --arg chan_pass "$channel_password" \
       '.teamtalk.hostname = $host | .teamtalk.tcp_port = $tcp | .teamtalk.udp_port = $udp | .teamtalk.encrypted = $enc | .teamtalk.nickname = $nick | .teamtalk.username = $user | .teamtalk.password = $pass | .teamtalk.channel = $chan | .teamtalk.channel_password = $chan_pass' \
       "$BOT_DIR/config.json" > "$tmp_config" && mv "$tmp_config" "$BOT_DIR/config.json"

    chown -R 1000:1000 "$BOT_DIR"
    
    docker create \
        --name "${bot_name}" \
        --network host \
        --label "role=ttmediabot" \
        --restart always \
        -v "${BOT_DIR}:/home/ttbot/TTMediaBot/data" \
        -v "${BOT_DIR}/cookies.txt:/home/ttbot/TTMediaBot/data/cookies.txt" \
        "${BOT_IMAGE}" > /dev/null 2>&1

    docker start "$bot_name"
    echo -e "${GREEN}تم إنشاء البوت وتشغيله بنجاح!${NC}"
    read -p "اضغط Enter للعودة..."
}

# وظيفة: إدارة البوتات
manage_bots() {
    header
    while true; do
        echo -e "${YELLOW} --- إدارة البوتات --- ${NC}"
        echo "1. تشغيل الكل"
        echo "2. إعادة تشغيل الكل"
        echo "3. إيقاف الكل"
        echo "4. حذف بوت"
        echo "5. تحديث الكوكيز (للجميع)"
        echo "6. العودة للقائمة الرئيسية"
        echo ""
        read -p "اختر خياراً: " opt_manage
        
        case $opt_manage in
            1)
                docker start $(docker ps -a -q -f "label=role=ttmediabot")
                echo "تم تشغيل جميع البوتات."
                sleep 1; header ;;
            2)
                docker stop -t 1 $(docker ps -a -q -f "label=role=ttmediabot")
                docker start $(docker ps -a -q -f "label=role=ttmediabot")
                echo "تمت إعادة تشغيل جميع البوتات."
                sleep 1; header ;;
            3)
                docker stop -t 1 $(docker ps -a -q -f "label=role=ttmediabot")
                echo "تم إيقاف جميع البوتات."
                sleep 1; header ;;
            4)
                read -p "اسم البوت المراد حذفه: " del_name
                docker rm -f "$del_name" && rm -rf "${BOTS_ROOT}/${del_name}"
                echo "تم الحذف."
                sleep 1; header ;;
            5)
                echo "يرجى لصق محتوى الكوكيز الجديد أدناه."
                echo "سيتم الحفظ تلقائياً بعد ثانية واحدة من انتهاء اللصق."
                new_cookies="/tmp/new_cookies.txt"
                > "$new_cookies"
                while IFS= read -t 1 -r line; do echo "$line" >> "$new_cookies"; done
                for d in "$BOTS_ROOT"/*; do
                    if [ -d "$d" ]; then
                        cp "$new_cookies" "$d/cookies.txt"
                        chown 1000:1000 "$d/cookies.txt"
                    fi
                done
                docker stop -t 1 $(docker ps -a -q -f "label=role=ttmediabot")
                docker start $(docker ps -a -q -f "label=role=ttmediabot")
                echo "تم تحديث الكوكيز وإعادة تشغيل البوتات."
                sleep 1; header ;;
            6) return ;;
        esac
    done
}

# التنفيذ الرئيسي
install_dependencies
build_image
mkdir -p "$BOTS_ROOT"

header
while true; do
    echo "1. إنشاء بوت جديد"
    echo "2. إدارة البوتات"
    echo "3. تحديث الكود / إعادة بناء الصورة"
    echo "4. حذف كل شيء (تنظيف شامل)"
    echo "5. خروج"
    echo ""
    read -p "اختر خياراً: " option
    
    case $option in
        1) create_bot; header ;;
        2) manage_bots; header ;;
        3) 
            docker build --build-arg CACHEBUST=$(date +%s) -t ${BOT_IMAGE} .
            recreate_bot_containers
            read -p "تم التحديث. اضغط Enter..."
            header ;;
        4)
            read -p "هل أنت متأكد من حذف كل شيء؟ (yes/no): " confirm
            if [ "$confirm" == "yes" ]; then
                docker stop $(docker ps -a -q -f "label=role=ttmediabot")
                docker rm $(docker ps -a -q -f "label=role=ttmediabot")
                docker rmi ${BOT_IMAGE}
                rm -rf "$BOTS_ROOT"
                echo "تم التنظيف الشامل."
            fi
            header ;;
        5) exit 0 ;;
    esac
done

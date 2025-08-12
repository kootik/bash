#!/bin/bash
# ~/.bash_functions.professional: Профессиональная коллекция shell-функций.
# Этот файл содержит проверенные, безопасные и эффективные функции.

# ==============================================================================
#   РАЗДЕЛ 0: СИСТЕМНЫЕ И СЕССИОННЫЕ ФУНКЦИИ
# ==============================================================================

# Сохраняет расширенную историю команд.
update_eternal_history() {
    # ИСПРАВЛЕНО: Все переменные объявлены как local для безопасности.
    local histfile_size
    histfile_size=$(stat -c %s "$HISTFILE" 2>/dev/null || echo 0)
    local history_line
    local history_sink
    local old_umask

    history -a
    # Проверяем, изменился ли файл истории, чтобы избежать лишних записей.
    ((histfile_size == $(stat -c %s "$HISTFILE" 2>/dev/null || echo 0))) && return

    history_line="${USER}\t${HOSTNAME}\t${PWD}\t$(history 1)"
    history_sink=$(readlink ~/.bash-ssh.history 2>/dev/null)

    # Если есть удаленный приемник истории (созданный sshb), отправляем туда.
    if [ -n "$history_sink" ]; then
        echo -e "$history_line" >"$history_sink" 2>/dev/null && return
    fi

    # Иначе пишем в локальный файл ~/.bash_eternal_history.
    old_umask=$(umask)
    umask 077
    echo -e "$history_line" >> ~/.bash_eternal_history
    umask "$old_umask"
}

# Продвинутая функция SSH для синхронизации окружения.
sshb() {
    local tmp_dir
    tmp_dir=$(mktemp -d ~/.ssh/sshb-control.XXXXXXXX)
    if [ -z "$tmp_dir" ]; then
        echo "Не удалось создать временный каталог." >&2
        return 1
    fi
    # Гарантированная очистка временного каталога при выходе из функции
    trap 'rm -rf "$tmp_dir"' RETURN

    local control_socket="${tmp_dir}/control-socket"
    local ssh="ssh -S ${control_socket}"
    local history_command="rm -f ~/.bash-ssh.history"
    local history_port

    # Список файлов для синхронизации окружения. Порядок важен.
    local env_files=(
        "$HOME/.bashrc"
        "$HOME/.bash_export"
        "$HOME/.bash_functions"
        "$HOME/.bash_aliases"
    )

    # УЛУЧШЕНО: Собираем в один пакет только существующие и читаемые файлы.
    local temp_bundle
    temp_bundle=$(mktemp)
    for file in "${env_files[@]}"; do
        [ -r "$file" ] && cat "$file" >> "$temp_bundle"
    done

    if [ -r ~/.bash-ssh ]; then
        history_port=$(basename "$(readlink ~/.bash-ssh.history 2>/dev/null)")
    fi

    # Создаем управляющее соединение в фоновом режиме.
    $ssh -fNM "$@" || { rm -f "$temp_bundle"; return 1; }

    # Если мы находимся во вложенной сессии, пробрасываем порт истории дальше.
    if [ -n "$history_port" ]; then
        local history_remote_port
        history_remote_port="$($ssh -O forward -R 0:127.0.0.1:"$history_port" placeholder)"
        history_command="ln -nsf /dev/tcp/127.0.0.1/$history_remote_port ~/.bash-ssh.history"
    fi

    # Отправляем наш собранный "пакет" на удаленный сервер.
    cat "$temp_bundle" | $ssh placeholder "command -v bash >/dev/null || { echo 'Ошибка: bash не найден на удаленном сервере!' >&2; exit 1; }; ${history_command}; cat >~/.bash-ssh"
    rm -f "$temp_bundle" # Очищаем локальный временный пакет

    # Запускаем интерактивную оболочку на удаленной машине с нашим окружением.
    $ssh "$@" -t 'SHELL=~/.bash-ssh; chmod +x $SHELL; exec bash --rcfile $SHELL -i'

    # Закрываем управляющее соединение при выходе.
    $ssh placeholder -O exit &> /dev/null
}

# --- Утилиты ---

# Создает резервную копию файла с временной меткой.
# Пример: bak /etc/nginx/nginx.conf
bak() {
    if [ -z "$1" ]; then
        echo "Использование: bak <имя_файла>" >&2
        return 1
    fi
    if [ ! -f "$1" ]; then
        echo "Ошибка: файл '$1' не найден." >&2
        return 1
    fi
    cp -iv "$1" "${1}.$(date +%F_%T)"
}

# Создает директорию и сразу переходит в нее.
# Пример: mkcd /tmp/new_project
mkcd() {
    if [ -z "$1" ]; then
        echo "Использование: mkcd <имя_каталога>" >&2
        return 1
    fi
    mkdir -p -- "$1" && cd -P -- "$1"
}

# -- Раздел 1: Управление файлами и архивами --

# Ищет ФАЙЛ по имени в текущем каталоге и его подкаталогах.
# Пример: ff "*.log"
ff() {
    if [ -z "$1" ]; then
        echo "Использование: ff \"<шаблон_имени_файла>\"" >&2
        return 1
    fi
    find . -type f -name "$1"
}

# Ищет КАТАЛОГ по имени в текущем каталоге и его подкаталогах.
# Пример: fd "docs"
fd() {
    if [ -z "$1" ]; then
        echo "Использование: fd \"<шаблон_имени_каталога>\"" >&2
        return 1
    fi
    find . -type d -name "$1"
}

# Перемещает указанные файлы или каталоги в системную корзину.
# Требует утилиты trash-cli (например, sudo apt install trash-cli)
# Использование: trash file.txt folder/
trash() {
    # Если trash-cli установлен, используем его
    if command -v trash-put &> /dev/null; then
        trash-put "$@"
        return
    fi

    # Запасной механизм
    local trash_dir="$HOME/.Trash"
    mkdir -p "$trash_dir"
    echo "Предупреждение: 'trash-put' не найден. Файлы будут перемещены в '$trash_dir'." >&2
    mv -v "$@" "$trash_dir"
}
# Универсальная функция для извлечения файлов из архивов.
# Пример: extract archive.zip backup.tar.gz
extract() {
    if [ $# -eq 0 ]; then
        echo "Использование: extract <файл> [файл2]..." >&2
        return 1
    fi
    for file in "$@"; do
        if [ ! -f "$file" ]; then
            echo "Ошибка: файл '$file' не найден." >&2
            continue
        fi
        case "$file" in
            *.tar.bz2|*.tbz2) tar xvjf "$file"    ;;
            *.tar.gz|*.tgz)   tar xvzf "$file"    ;;
            *.tar.xz|*.txz)   tar xvJf "$file"    ;;
            *.tar)            tar xvf "$file"     ;;
            *.zip)            unzip "$file"       ;;
            *.rar)            if command -v unrar &>/dev/null; then unrar x "$file"; else echo "Ошибка: 'unrar' не найден." >&2; fi ;;
            *.gz)             gunzip "$file"      ;;
            *.bz2)            bunzip2 "$file"     ;;
            *.xz)             unxz "$file"        ;;
            *.7z)             if command -v 7z &>/dev/null; then 7z x "$file"; else echo "Ошибка: '7z' не найден." >&2; fi ;;
            *)                echo "Неизвестный тип архива: '$file'" >&2 ;;
        esac
    done
}


# Создает .tar.gz архив.
# Пример: targz my_folder
targz() {
    if [ -z "$1" ]; then
        echo "Использование: targz <источник> [архив.tar.gz]" >&2
        return 1
    fi
    if [ ! -e "$1" ]; then
        echo "Ошибка: источник '$1' не существует." >&2
        return 1
    fi
    local target_name="${1%/}"
    local output_name="${2:-$target_name.tar.gz}"
    echo "Создание архива: $output_name"
    tar -czvf "$output_name" "$target_name"
}

# Создает .zip архив с исключениями.
# Пример: zipf source_code_folder
zipf() {
    if [ -z "$1" ]; then
        echo "Использование: zipf <источник> [архив.zip]" >&2
        return 1
    fi
    if [ ! -e "$1" ]; then
        echo "Ошибка: источник '$1' не существует." >&2
        return 1
    fi
    local target_name="${1%/}"
    local output_name="${2:-$target_name.zip}"
    echo "Создание архива: $output_name"
    zip -r "$output_name" "$target_name" -x "*.git*" "*.DS_Store*" "__MACOSX*"
}
# Поиск текста в файлах рекурсивно.
# Пример: fsearch "error" ./*.log
fsearch() {
    if [ $# -lt 2 ]; then
        echo "Использование: fsearch <текст> <файлы/директории>" >&2
        return 1
    fi
    local text="$1"
    shift
    grep -rnwE "$@" -e "$text"
}
# --- Сетевые утилиты ---
# Выполняет DNS-запрос через Google DNS-over-HTTPS.
# Пример: doh google.com
doh() {
    if ! command -v jq &>/dev/null; then
        echo "Ошибка: 'jq' не найден." >&2
        return 1
    fi
    if [ -z "$1" ]; then
        echo "Использование: doh <доменное_имя>" >&2
        return 1
    fi
    curl -s -H 'accept: application/dns+json' "https://dns.google.com/resolve?name=$1" | jq
}

# Показывает погоду для указанного города.
# Пример: weather London
weather() {
    local city="${1:-Moscow}"
    curl -s "wttr.in/${city}?format=4"
}

# "Умное" завершение процесса по имени.
# Пример: killg chrome
killg() {
    if [ -z "$1" ]; then
        echo "Использование: killg <имя_процесса>" >&2
        return 1
    fi

    if ! pgrep -fi "$1" > /dev/null; then
        echo "Процессы, содержащие '$1', не найдены."
        return 0
    fi

    echo "Попытка завершить процессы '$1' от имени текущего пользователя..."
    pkill -fi "$1" &>/dev/null

    if ! pgrep -fi "$1" > /dev/null; then
        echo "Процессы успешно завершены."
        return 0
    fi

    read -p "Не удалось завершить от имени текущего пользователя. Использовать sudo? (y/n): " confirm
    if [[ $confirm != [yY] ]]; then
        echo "Операция отменена."
        return 1
    fi

    echo "Повышение прав до sudo..."
    sudo pkill -f -i -9 "$1" &>/dev/null

    if ! pgrep -fi "$1" > /dev/null; then
        echo "Процессы успешно завершены с правами sudo."
    else
        echo "Не удалось завершить процессы даже с правами sudo." >&2
        return 1
    fi
}
# -- Раздел 2: Навигация и системная информация --

# Переходит в каталог и выводит его содержимое.
# Пример: cl /var/log
cl() {
    local dir="${1:-$HOME}"
    if [ -d "$dir" ]; then
        cd "$dir" && ls -F --color=auto
    else
        echo "Ошибка: каталог '$dir' не найден." >&2
        return 1
    fi
}

# Показывает использование дискового пространства с улучшенным форматированием.
# Пример: dfh
dfh() {
    if command -v pydf &>/dev/null; then
        pydf
    else
        df -Tha --total
    fi
}

# Показывает суммарный размер указанного каталога.
# Пример: duh /var/www
duh() {
    if [ -z "$1" ]; then
        du -sh .
    else
        du -sh "$1"
    fi
}

# Показывает размер подкаталогов в указанном пути, отсортированный по убыванию.
# Пример: dus /var
dus() {
    # Используем "$@" для передачи всех аргументов (например, пути) в du.
    # Если аргументы не переданы, используется текущий каталог ".".
    du -h --max-depth=1 "${@:-.}" | sort -rh
}

# Показывает список доступных функций с их описанием и примерами.
# Пример: h-func
h-func() {
    echo -e "\n\e[1;32mПОЛЬЗОВАТЕЛЬСКИЕ ФУНКЦИИ (подсказка)\e[0m"
    awk '
        /^#/ {
            if (comment1 == "") {
                comment1 = $0;
                sub(/^#\s*/, "", comment1);
            } else {
                comment2 = $0;
                sub(/^#\s*/, "", comment2);
            }
            next;
        }
        /^[a-zA-Z0-9_-]+\(\)/ {
            func_name = $0;
            sub(/\(\).*/, "", func_name);
            print func_name "\t" comment1 "\t" comment2;
            comment1 = "";
            comment2 = "";
        }
        /^$/ {
            comment1 = "";
            comment2 = "";
        }
    ' "$HOME/.bash_functions" | \
    sort -f | \
    awk -F'\t' '{
        printf "  \033[1;33m%-18s\033[0m - %s\n", $1, $2;
        if ($3 != "") {
            printf "  %-18s  \033[2m%s\033[0m\n", "", $3;
        }
    }'
    echo ""
}

# Показывает список доступных псевдонимов (aliases) с их описанием.
# Пример: h-alias
h-alias() {
    echo -e "\n\e[1;32mПОЛЬЗОВАТЕЛЬСКИЕ ПСЕВДОНИМЫ (подсказка)\e[0m"
    awk '
        /^# --.*--$/ {
            title = $0;
            sub(/^# -- /, "", title);
            sub(/ --$/, "", title);
            printf "\n\033[1;34m%s\033[0m\n", title;
            next;
        }
        /^\s*alias/ {
            line = $0;
            comment = "Нет описания";
            if (match(line, /#.*/)) {
                comment = substr(line, RSTART + 1);
                sub(/^\s*/, "", comment);
                sub(/\s*#.*/, "", line);
            }
            sub(/^\s*alias\s*/, "", line);
            sub(/\s*=.*/, "", line);
            alias_name = line;
            printf "  \033[1;33m%-18s\033[0m - %s\n", alias_name, comment;
        }
    ' "$HOME/.bash_aliases"
    echo ""
}

# Предоставляет краткую сводку о системе.
# Пример: sysinfo
sysinfo() {
    # Секция ОС
    (
        . /etc/os-release 2>/dev/null
        echo -e "\n\e[1;32mОПЕРАЦИОННАЯ СИСТЕМА\e[0m"
        echo "  ОС:           ${PRETTY_NAME:-$(uname -s)}"
        echo "  Ядро:         $(uname -r)"
        echo "  Архитектура:  $(uname -m)"
        echo "  Время работы: $(uptime -p | sed "s/up //")"
        echo ""
    )

    # Секция ресурсов
    echo -e "\e[1;32mРЕСУРСЫ\e[0m"
    free -h
    echo ""
    df -h 
    echo ""

    # Секция процессора
    echo -e "\e[1;32mПРОЦЕССОР\e[0m"
    lscpu | grep -E "Model name|CPU\(s\)|Vendor ID|Socket\(s\)"
    echo ""

    # Секция сети
    echo -e "\e[1;32mСЕТЬ\e[0m"
    echo -e "  Имя хоста:    $(hostname)"
    echo "  IP-адреса:"
    if command -v ip &>/dev/null; then
        ip -br a | awk '{printf "    %-15s %s\n", $1, $3}'
    elif command -v ifconfig &>/dev/null; then  # Fallback для старых систем или macOS
        ifconfig | grep "inet " | awk '{print "    " $2}'
    else
        echo "    Не удалось получить IP (установите ip или ifconfig)."
    fi
    echo ""
}

# Показ топ процессов по CPU.
# Пример: topcpu 5
topcpu() {
    local num="${1:-10}"
    ps aux --sort=-%cpu | head -n "$((num + 1))"
}

# -- Раздел 3: Сеть и сеанс --

# Выполняет DNS-запрос для указанного типа записи (A, MX, TXT, etc.).
# Пример: digx google.com MX
digx() {
    if [ -z "$1" ]; then
        echo "Использование: digx <домен> [тип_записи]" >&2
        return 1
    fi
    dig +nocmd "$1" "${2:-A}" +noall +answer
}

# Проверяет, открыт ли TCP-порт на хосте.
# Пример: checkport example.com 443
checkport() {
    if nc -z -v -w 2 "$1" "$2" &> /dev/null; then
        echo "Порт $2 на $1 открыт"
    else
        echo "Порт $2 на $1 закрыт"
    fi
}

# "Умная" блокировка экрана.
# Пример: lock
lock() {
    if command -v xdg-screensaver &>/dev/null; then
        xdg-screensaver lock
    elif command -v loginctl &>/dev/null; then
        loginctl lock-session
    elif command -v gnome-screensaver-command &>/dev/null; then
        gnome-screensaver-command -l
    elif command -v xflock4 &>/dev/null; then
        xflock4
    else
        echo "Не найдена команда для блокировки экрана." >&2
        return 1
    fi
}

# -- Раздел 4: Инструменты разработчика --

# Показывает и отслеживает логи для указанного systemd-юнита.
# Пример: jnl-unit nginx.service
jnl-unit() {
    if [ -z "$1" ]; then
        echo "Использование: jnl-unit <имя_юнита>" >&2
        return 1
    fi
    sudo journalctl -u "$1" -f --no-pager
}

# Добавляет все, делает коммит и отправляет в удаленный репозиторий.
# Пример: gacp "feat: add new login form"
gacp() {
    if [ -z "$1" ]; then
        echo "Ошибка: необходимо указать сообщение коммита." >&2
        return 1
    fi
    git add --all && git commit -m "$1" && git push
}

# Создает новую ветку, отправляет ее в origin и устанавливает отслеживание.
# Пример: gnewbranch feature/PROJ-123
gnewbranch() {
    if [ -z "$1" ]; then
        echo "Ошибка: необходимо указать имя новой ветки." >&2
        return 1
    fi
    git checkout -b "$1" && git push -u origin "$1"
}

# Удаляет локальные ветки, которые уже были слиты в основную ветку.
# Пример: gprune
gprune() {
    git fetch --all --prune
    local main_branch
    if git show-ref --verify --quiet refs/heads/main; then
        main_branch="main"
    elif git show-ref --verify --quiet refs/heads/master; then
        main_branch="master"
    else
        echo "Не удалось определить основную ветку (main или master)." >&2
        return 1
    fi
    echo "Основная ветка: $main_branch. Удаление слитых веток..."
    git branch --merged "$main_branch" | grep -vE "^\*|^\s*$main_branch$" | xargs -r git branch -d
    echo "Очистка завершена."
}

# Быстрая очистка Docker.
# Пример: dclean
dclean() {
    if ! command -v docker &>/dev/null; then
        echo "Ошибка: 'docker' не найден." >&2
        return 1
    fi
    echo "Удаление остановленных контейнеров..."
    docker container prune -f
    echo "Удаление неиспользуемых образов, сетей и кэша сборки..."
    docker system prune -af
}

# Создает, активирует и обновляет pip в новом виртуальном окружении Python.
# Пример: mkvenv my-project-env
mkvenv() {
    if [ -z "$1" ]; then
        echo "Ошибка: необходимо указать имя для виртуального окружения."
        return 1
    fi
    python3 -m venv "$1" && \
    source "$1/bin/activate" && \
    pip install -U pip wheel && \
    echo "Окружение '$1' создано и активировано."
}

# Генератор случайных паролей.
# Пример: genpass 16
genpass() {
    local length="${1:-12}"
    tr -dc 'A-Za-z0-9!@#$%^&*()_+' < /dev/urandom | head -c "$length"
    echo
}
# -- Раздел 5: Утилиты --

# Ищет запущенные процессы по имени, исключая сам процесс поиска.
# Пример: psg "nginx|php-fpm"
psg() {
  ps aux | grep -v grep | grep -Ei --color=auto "$@"
}

# Ищет в истории команд по заданному шаблону.
# Пример: hg "docker ps"
hg() {
    history | grep -E --color=auto "$@"
}

#   clbin - Загружает данные на clbin.com
#   clbin my_file.txt
#   clbin my_directory/
#
clbin() {
    if ! command -v curl &>/dev/null; then
        echo "Ошибка: команда 'curl' не найдена." >&2
        return 1
    fi

    # Случай 1: Данные поступают из stdin (пайп)
    if [ ! -t 0 ]; then
        curl --progress-bar -F 'clbin=<-' https://clbin.com
        return
    fi

    # Случай 2: Данные передаются как аргументы
    if [ $# -eq 0 ]; then
        echo "Использование: <команда> | clbin" >&2
        echo "       или: clbin <файл>" >&2
        echo "       или: clbin <каталог>" >&2
        return 1
    fi

    local target="$1"

    if [ ! -e "$target" ]; then
        echo "Ошибка: '$target' не найден." >&2
        return 1
    fi

    # Аргумент - это каталог
    if [ -d "$target" ]; then
        if ! command -v zip &>/dev/null; then
            echo "Ошибка: команда 'zip' не найдена для архивации каталога." >&2
            return 1
        fi
        echo "Архивация каталога '$target' и отправка..." >&2
        zip -r -q - "$target" | curl --progress-bar -F 'clbin=<-' https://clbin.com

    # Аргумент - это файл
    elif [ -f "$target" ]; then
        cat "$target" | curl --progress-bar -F 'clbin=<-' https://clbin.com
    else
        echo "Ошибка: '$target' не является файлом или каталогом." >&2
        return 1
    fi
}



# Извлекает указанные столбцы из стандартного ввода.
# Пример: ls -l | extract_column 1 9
extract_column() {
    awk -v cols_str="$*" '
    BEGIN {
        n = split(cols_str, ranges, " ");
        for (i = 1; i <= n; i++) {
            if (ranges[i] ~ /^[0-9]+-[0-9]+$/) {
                split(ranges[i], r, "-");
                for (j = r[1]; j <= r[2]; j++) cols[j] = 1;
            } else if (ranges[i] ~ /^[0-9]+-$/) {
                split(ranges[i], r, "-");
                col_from = r[1];
            } else { cols[ranges[i]] = 1; }
        }
    }
    {
        line = "";
        for (i = 1; i <= NF; i++) {
            if (i in cols || (col_from && i >= col_from)) {
                line = (line == "" ? $i : line " " $i);
            }
        }
        if (line!= "") print line;
    }'
}

# Определяет ОС и создает псевдонимы для управления пакетами.
# (Вызывается автоматически при запуске)
setup_os_aliases() {
    if [[ "$(uname)" == "Darwin" ]]; then
        if command -v brew &>/dev/null; then
            alias update='brew update && brew upgrade'
            alias install='brew install'
            alias remove='brew uninstall'
            alias search='brew search'
        fi
    elif [ -f /etc/os-release ]; then
       . /etc/os-release
        case "$ID" in
            ubuntu|debian|mint)
                alias update='sudo apt update && sudo apt full-upgrade -y'
                alias install='sudo apt install -y'
                alias remove='sudo apt autoremove --purge -y'
                alias search='apt-cache search'
                ;;
            fedora|centos|rhel)
                alias update='sudo dnf upgrade -y'
                alias install='sudo dnf install -y'
                alias remove='sudo dnf remove -y'
                alias search='dnf search'
                ;;
            arch|manjaro)
                alias update='sudo pacman -Syu'
                alias install='sudo pacman -S --noconfirm'
                alias remove='sudo pacman -Rns --noconfirm'
                alias search='pacman -Ss'
                ;;
        esac
    fi
}


#   РАЗДЕЛ 6: ИНТЕРАКТИВНЫЕ ФУНКЦИИ GIT С ИСПОЛЬЗОВАНИЕМ FZF


# Интерактивно переключиться на другую ветку Git.
# Пример: Начните вводить имя ветки для поиска и нажмите Enter.
gfb() {

    if ! command -v fzf &>/dev/null; then
        echo "Ошибка: команда 'fzf' не найдена." >&2
        return 1
    fi

    local branch
    branch=$(git for-each-ref --count=30 --sort=-committerdate refs/heads/ --format="%(refname:short)" |
        fzf --preview 'git log --color=always --oneline -n 15 {}' --reverse)
    
    if [ -n "$branch" ]; then
        git checkout "$branch"
    fi
}

# Интерактивно просмотреть историю коммитов (git log).
# Пример: Нажмите Enter для деталей, Ctrl-D для просмотра diff.
gfl() {
    if ! command -v fzf &>/dev/null; then echo "Ошибка: fzf не найден." >&2; return 1; fi
    git log --graph --color=always \
        --format="%C(auto)%h%d %s %C(black)%C(bold)%cr" "$@" |
    fzf --ansi --no-sort --reverse --tiebreak=index --preview \
        'f() { set -- $(echo -- "$@" | grep -o "[a-f0-9]\{7\}"); [ $# -eq 0 ] || git show --color=always $1; }; f {}' \
        --header "ENTER: полный коммит | CTRL-D: дифф" \
        --bind "enter:execute:echo {} | grep -o '[a-f0-9]\{7\}' | head -1 | xargs -I % sh -c 'git show --color=always % | less -R'" \
        --bind "ctrl-d:execute:echo {} | grep -o '[a-f0-9]\{7\}' | head -1 | xargs -I % sh -c 'git diff --color=always %^ % | less -R'"
}

# Интерактивно выбрать файлы для добавления в коммит (git add).
# Пример: Выберите файлы клавишей Tab и нажмите Enter.
gfa() {
    if ! command -v fzf &>/dev/null; then
        echo "Ошибка: команда 'fzf' не найдена." >&2
        return 1
    fi

    local files
    files=$(git -c color.status=always status --short |
        fzf -m --ansi --nth 2.. --preview 'git diff --color=always -- {-1} | sed "s/.* //"' |
        cut -c 4-)
    if [ -n "$files" ]; then
        # Безопасная обработка имен файлов с пробелами
        echo "$files" | while IFS= read -r file; do
            git add -- "$file"
        done
        git status -sb
    fi
}

# Интерактивно восстановить версию файла из любого коммита.
# Пример: Сначала выберите коммит, затем выберите файл для восстановления.
gfc() {
    if ! command -v fzf &>/dev/null; then echo "Ошибка: fzf не найден." >&2; return 1; fi
    local commit file
    commit=$(git log --oneline --color=always | fzf --ansi --preview 'git show --color=always {+1}' | awk '{print $1}')
    if [ -n "$commit" ]; then
        file=$(git diff-tree --no-commit-id --name-only -r "$commit" | fzf --preview "git show --color=always $commit:{}")
        if [ -n "$file" ]; then
            git checkout "$commit" -- "$file"
        fi
    fi
}

# Интерактивно удалить одну или несколько локальных веток.
# Пример: Выберите ветки клавишей Tab и нажмите Enter для удаления.
gfd() {
    if ! command -v fzf &>/dev/null; then
        echo "Ошибка: команда 'fzf' не найдена." >&2
        return 1
    fi

    local branches
    branches=$(git branch | grep -vE '^\*|main|master' | fzf -m --preview 'git log --color=always --oneline -n 10 {}')
    if [ -n "$branches" ]; then
        # Безопасная обработка имен веток
        echo "$branches" | while IFS= read -r branch; do
            # Удаляем пробелы, которые может добавить fzf
            git branch -d "$(echo "$branch" | xargs)"
        done
    fi
}

# 
#   РАЗДЕЛ 7: ПРОЧИЕ УТИЛИТЫ


# Переходит вверх по иерархии каталогов.
# Пример: up 3
up() {
    local count=${1:-1}
    local path=""
    for ((i=0; i<count; i++)); do
        path+="../"
    done
    cd "$path"
}

# Калькулятор с поддержкой чисел с плавающей точкой.
# Пример: calc "10 / 3"
calc() {
    if [ -z "$1" ]; then
        echo "Использование: calc \"выражение\"" >&2
        return 1
    fi
    echo "scale=10; $1" | bc -l | sed -E 's/([.0-9]*[1-9])0+$|\.0+$/\1/'
}

# Быстрое резервное копирование домашней директории с исключением файла бекапа и загрузок.
# Пример: backup_home /path/to/backup.tar.gz
backup_home() {
    local output="${1:-$HOME/backup_$(date +%F).tar.gz}"
    echo "Создание резервной копии в $output..."
    tar -czvf "$output" \
        --exclude="$HOME/.cache" \
        --exclude="$HOME/Downloads" \
        --exclude="$HOME/.npm" \
        --exclude="$HOME/.rustup" \
        --exclude="$HOME/.local/share/Trash" \
        --exclude="*/node_modules" \
        --exclude="*/target" \
        --exclude="$output" \
        "$HOME"
    echo "Резервная копия успешно создана."
}


#   РАЗДЕЛ 8: УТИЛИТЫ ДЛЯ МОНИТОРИНГА


# Мониторинг изменений в файле с помощью указанной команды.
# Пример: wfile /var/log/syslog tail
wfile() {
    if [ $# -lt 2 ]; then
        echo "Использование: wfile <файл> <команда_для_запуска>" >&2
        return 1
    fi
    local file="$1"
    shift
    watch -n 1 -d -- "$@" "$file"
}

# Интерактивный rebase на выбранный коммит из лога.
# Пример: gfr
gfr() {
    if ! command -v fzf &>/dev/null; then echo "Ошибка: fzf не найден." >&2; return 1; fi

    local commit
    commit=$(git log --oneline --color=always | fzf --ansi --preview 'git show --color=always {+1}' | awk '{print $1}')

    if [ -n "$commit" ]; then
        git rebase -i "$commit"
    fi
}

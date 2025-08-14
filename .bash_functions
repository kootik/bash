#!/bin/bash
# ~/.bash_functions.professional: Профессиональная коллекция shell-функций.
# Этот файл содержит проверенные, безопасные и эффективные функции.

# ==============================================================================
#   РАЗДЕЛ 0: ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ (HELPERS)
# ==============================================================================

# Проверяет, существует ли команда в системе.
# Это более надежная и читаемая альтернатива `command -v`.
# Пример: if command_exists "docker"; then ...
command_exists() {
    # `hash` - это встроенная команда Bash, которая ищет команду в $PATH
    # и кэширует ее. Перенаправление вывода в /dev/null скрывает
    # сообщение об успехе или ошибке.
    hash "$1" 2>/dev/null
}

# ==============================================================================
#   РАЗДЕЛ 1: СИСТЕМНЫЕ И СЕССИОННЫЕ ФУНКЦИИ
# ==============================================================================

# --- Утилиты ---

# Создает резервную копию файла с временной меткой.
# Пример: bak /etc/nginx/nginx.conf
bak() {
    if [ -z "$1" ]; then
        echo "Использование: bak <имя_файла>" >&2
        return 1
    fi
    if [ ! -e "$1" ]; then
        echo "Ошибка: '$1' не найден." >&2
        return 1
    fi
    local timestamp
    timestamp=$(date +%Y-%m-%d_%H-%M-%S)
    echo "Создание резервной копии..."
    cp -av "$1" "${1}.bak.${timestamp}"
}

# Более гибкая версия для поиска "тяжелых" файлов/папок
# Использование: dut [ПУТЬ] [ГЛУБИНА] [КОЛ-ВО_СТРОК]
# Пример: dut /var/log 2 10
dut() {
  local path=${1:-.}
  local depth=${2:-2}
  local count=${3:-20}
  echo "🔍 Поиск в '$path' на глубину '$depth' (топ $count):"
  command du -h --max-depth="$depth" "$path" 2>/dev/null | command sort -rh | command head -n "$count"
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
    if command_exists "fd"; then
        fd --type f --glob "$1"
    else
        find . -type f -iname "$1"
    fi
}

# Ищет КАТАЛОГ по имени в текущем каталоге и его подкаталогах.
# Пример: fdd "docs"
fdd() {
    if [ -z "$1" ]; then
        echo "Использование: fdd \"<шаблон_имени_каталога>\"" >&2
        return 1
    fi
    if command_exists "fd"; then
        fd --type d --glob "$1"
    else
        find . -type d -iname "$1"
    fi
}

# Перемещает указанные файлы или каталоги в системную корзину.
# Требует утилиты trash-cli (например, sudo apt install trash-cli)
# Использование: trash file.txt folder/
trash() {
    if command_exists "trash-put"; then
        trash-put "$@"
        return
    fi
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
            *.rar)            if command_exists "unrar"; then unrar x "$file"; else echo "Ошибка: 'unrar' не найден." >&2; fi ;;
            *.gz)             gunzip "$file"      ;;
            *.bz2)            bunzip2 "$file"     ;;
            *.xz)             unxz "$file"        ;;
            *.7z)             if command_exists "7z"; then 7z x "$file"; else echo "Ошибка: '7z' не найден." >&2; fi ;;
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
    if ! command_exists "jq"; then
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
    if command_exists "pydf"; then
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
    du -h --max-depth=1 "${@:-.}" | sort -rh
}

# Показывает список доступных функций с их описанием и примерами.
# Пример: h-func
h-func() {
    local source_file="$HOME/.bash_functions"
    if [[ "$SHELL" == *".bash-ssh" ]]; then
        source_file="$SHELL"
    fi
    if [ ! -f "$source_file" ]; then echo "Файл с функциями не найден: $source_file" >&2; return 1; fi
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
    ' "$source_file" | \
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
    local source_file="$HOME/.bash_aliases"
    if [[ "$SHELL" == *".bash-ssh" ]]; then
        source_file="$SHELL"
    fi
    if [ ! -f "$source_file" ]; then echo "Файл с псевдонимами не найден: $source_file" >&2; return 1; fi
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
    ' "$source_file"
    echo ""
}

# Предоставляет краткую сводку о системе.
# Пример: sysinfo
sysinfo() {
    (
        . /etc/os-release 2>/dev/null
        echo -e "\n\e[1;32mОПЕРАЦИОННАЯ СИСТЕМА\e[0m"
        echo "  ОС:           ${PRETTY_NAME:-$(uname -s)}"
        echo "  Ядро:         $(uname -r)"
        echo "  Архитектура:  $(uname -m)"
        echo "  Время работы: $(uptime -p | sed "s/up //")"
        echo ""
    )
    echo -e "\e[1;32mРЕСУРСЫ\e[0m"
    free -h
    echo ""
    df -h 
    echo ""
    echo -e "\e[1;32mПРОЦЕССОР\e[0m"
    lscpu | grep -E "Model name|CPU\(s\)|Vendor ID|Socket\(s\)"
    echo ""
    echo -e "\e[1;32mСЕТЬ\e[0m"
    echo -e "  Имя хоста:    $(hostname)"
    echo "  IP-адреса:"
    if command_exists "ip"; then
        ip -br a | awk '{printf "    %-15s %s\n", $1, $3}'
    elif command_exists "ifconfig"; then
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
    if command_exists "xdg-screensaver"; then
        xdg-screensaver lock
    elif command_exists "loginctl"; then
        loginctl lock-session
    elif command_exists "gnome-screensaver-command"; then
        gnome-screensaver-command -l
    elif command_exists "xflock4"; then
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
    if ! command_exists "docker"; then
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
    if ! command_exists "curl"; then
        echo "Ошибка: команда 'curl' не найдена." >&2
        return 1
    fi
    if [ ! -t 0 ]; then
        curl --progress-bar -F 'clbin=<-' https://clbin.com
        return
    fi
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
    if [ -d "$target" ]; then
        if ! command_exists "zip"; then
            echo "Ошибка: команда 'zip' не найдена для архивации каталога." >&2
            return 1
        fi
        echo "Архивация каталога '$target' и отправка..." >&2
        zip -r -q - "$target" | curl --progress-bar -F 'clbin=<-' https://clbin.com
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
        if command_exists "brew"; then
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
    if ! command_exists "fzf"; then
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
    if ! command_exists "fzf"; then echo "Ошибка: fzf не найден." >&2; return 1; fi
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
    if ! command_exists "fzf"; then
        echo "Ошибка: команда 'fzf' не найдена." >&2
        return 1
    fi
    local files
    files=$(git -c color.status=always status --short |
        fzf -m --ansi --nth 2.. --preview 'git diff --color=always -- {-1} | sed "s/.* //"' |
        cut -c 4-)
    if [ -n "$files" ]; then
        echo "$files" | while IFS= read -r file; do
            git add -- "$file"
        done
        git status -sb
    fi
}

# Интерактивно восстановить версию файла из любого коммита.
# Пример: Сначала выберите коммит, затем выберите файл для восстановления.
gfc() {
    if ! command_exists "fzf"; then echo "Ошибка: fzf не найден." >&2; return 1; fi
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
    if ! command_exists "fzf"; then
        echo "Ошибка: команда 'fzf' не найдена." >&2
        return 1
    fi
    local branches
    branches=$(git branch | grep -vE '^\*|main|master' | fzf -m --preview 'git log --color=always --oneline -n 10 {}')
    if [ -n "$branches" ]; then
        echo "$branches" | while IFS= read -r branch; do
            git branch -d "$(echo "$branch" | xargs)"
        done
    fi
}

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
    if ! command_exists "fzf"; then echo "Ошибка: fzf не найден." >&2; return 1; fi
    local commit
    commit=$(git log --oneline --color=always | fzf --ansi --preview 'git show --color=always {+1}' | awk '{print $1}')
    if [ -n "$commit" ]; then
        git rebase -i "$commit"
    fi
}

# Интерактивно переключить текущее пространство имен (namespace).
# Пример: kns (появится список для выбора)
kns() {
    if ! command_exists "fzf"; then echo "Ошибка: fzf не найден." >&2; return 1; fi
    local ns
    ns=$(kubectl get ns -o name | sed 's/namespace\///' | fzf --height 40% --reverse --prompt="Выберите Namespace: ")
    if [[ -n "$ns" ]]; then
        kubectl config set-context --current --namespace="$ns"
    fi
}

# Интерактивно переключить текущий контекст (кластер).
# Пример: kctx (появится список для выбора)
kctx() {
    if ! command_exists "fzf"; then echo "Ошибка: fzf не найден." >&2; return 1; fi
    local ctx
    ctx=$(kubectl config get-contexts -o name | fzf --height 40% --reverse --prompt="Выберите Контекст: ")
    if [[ -n "$ctx" ]]; then
        kubectl config use-context "$ctx"
    fi
}

# Декодировать секрет Kubernetes из Base64.
# Пример: kdecode my-secret db-password
kdecode() {
    if [ $# -lt 1 ]; then
        echo "Использование: kdecode <имя_секрета> [ключ]" >&2
        return 1
    fi
    local secret_name="$1"
    local key="$2"
    if [ -n "$key" ]; then
        kubectl get secret "$secret_name" -o "jsonpath={.data.$key}" | base64 --decode
        echo # Добавляем перенос строки для чистоты вывода
    else
        kubectl get secret "$secret_name" -o json | jq -r '.data | to_entries[] | "\(.key): \(.value | @base64d)"'
    fi
}

# Проверить SSL-сертификат домена: кем выдан, кому и срок действия.
# Пример: check_ssl google.com
check_ssl() {
    local domain="${1}"
    if [ -z "$domain" ]; then
        echo "Использование: check_ssl <домен>" >&2
        return 1
    fi
    echo "Проверка сертификата для ${domain}..."
    echo | openssl s_client -servername "${domain}" -connect "${domain}:443" 2>/dev/null | openssl x509 -noout -text | grep -E "Issuer:|Subject:|Not Before|Not After"
}

# Быстро декодировать токен JWT (полезно для API и аутентификации).
# Пример: jwtdec <длинный_токен_jwt>
jwtdec() {
    if [ -z "$1" ]; then
        echo "Использование: jwtdec <токен>" >&2
        return 1
    fi
    local jq_cmd="cat"
    if command_exists "jq"; then
        jq_cmd="jq ."
    fi
    {
        echo -e "\n\033[1;34m--- HEADER ---\033[0m"
        echo "$1" | cut -d'.' -f1 | base64 --decode 2>/dev/null | $jq_cmd
        echo -e "\n\033[1;34m--- PAYLOAD ---\033[0m"
        echo "$1" | cut -d'.' -f2 | base64 --decode 2>/dev/null | $jq_cmd
        echo
    }
}

# Интерактивно "запрыгнуть" в работающий Docker-контейнер.
# Пример: d_dive (появится список контейнеров для выбора)
d_dive() {
    if ! command_exists "docker" || ! command_exists "fzf"; then
        echo "Ошибка: для этой функции требуются 'docker' и 'fzf'." >&2
        return 1
    fi
    if ! docker info >/dev/null 2>&1; then
        echo "Ошибка: Docker daemon не запущен." >&2
        return 1
    fi
    local container
    container_list=$(docker ps --format "{{.ID}}\t{{.Names}}\t{{.Image}}")
    if [[ -z "$container_list" ]]; then
        echo "Не найдено ни одного запущенного контейнера." >&2
        return 0
    fi
    container=$(echo "$container_list" | fzf --height 40% --reverse --header "Выберите контейнер:")
    if [[ -n "$container" ]]; then
        local container_id
        container_id=$(echo "$container" | awk '{print $1}')
        echo "Подключение к контейнеру $container_id..."
        docker exec -it "$container_id" bash || docker exec -it "$container_id" sh
    fi
}

# Показать логи контейнера с возможностью слежения (follow).
# Пример: dlogs (выбрать контейнер), dlogs -f (выбрать и следить)
dlogs() {
    if ! command_exists "docker" || ! command_exists "fzf"; then
        echo "Ошибка: для этой функции требуются 'docker' и 'fzf'." >&2
        return 1
    fi
    if ! docker info >/dev/null 2>&1; then
        echo "Ошибка: Docker daemon не запущен." >&2
        return 1
    fi
    local container
    container_list=$(docker ps -a --format "{{.ID}}\t{{.Names}}\t{{.Image}}")
    if [[ -z "$container_list" ]]; then
        echo "Не найдено ни одного контейнера." >&2
        return 0
    fi
    container=$(echo "$container_list" | fzf --height 40% --reverse --header "Выберите контейнер для просмотра логов:")
    if [[ -n "$container" ]]; then
        local container_id
        container_id=$(echo "$container" | awk '{print $1}')
        docker logs "$@" "$container_id"
    fi
}

# Интерактивно переключиться на другой Terraform workspace.
# Требует: terraform, fzf
# Пример: tfswitch (появится список для выбора)
tfswitch() {
    if ! command_exists "terraform" || ! command_exists "fzf"; then
        echo "Ошибка: для этой функции требуются 'terraform' и 'fzf'." >&2
        return 1
    fi
    if [ ! -d ".terraform" ]; then
        echo "Ошибка: Каталог .terraform не найден. Выполните 'terraform init' сначала." >&2
        return 1
    fi
    local workspace
    workspace=$(terraform workspace list | sed 's/^[ *]*//' | fzf --height 20% --reverse --prompt="Выберите workspace: ")
    if [[ -n "$workspace" ]]; then
        terraform workspace select "$workspace"
    fi
}

# Синхронизировать форк с оригинальным (upstream) репозиторием.
# Предполагается, что у вас уже добавлен remote с именем 'upstream'.
# Пример: gsync
gsync() {
    if ! git remote -v | grep -q "^upstream"; then
        echo "Ошибка: remote с именем 'upstream' не найден." >&2
        echo "Добавьте его: git remote add upstream <URL_оригинального_репозитория>"
        return 1
    fi
    local current_branch
    current_branch=$(git rev-parse --abbrev-ref HEAD)
    local main_branch="main" # Или 'master', если используется он
    echo "Переключение на ветку '${main_branch}'..."
    git checkout "$main_branch"
    echo "Получение изменений из 'upstream'..."
    git fetch upstream
    echo "Слияние 'upstream/${main_branch}' в локальную '${main_branch}'..."
    git merge "upstream/${main_branch}"
    echo "Возврат на исходную ветку '${current_branch}'..."
    git checkout "$current_branch"
    echo "Синхронизация завершена. Теперь вы можете сделать 'git rebase ${main_branch}' в ваших feature-ветках."
}

# Создать дамп базы данных PostgreSQL, выбирая ее интерактивно.
# Требует: pg_dump, psql, fzf
# Пример: pg_backup
# Пример с указанием пользователя: pg_backup myuser
pg_backup() {
    if ! command_exists "fzf" || ! command_exists "psql"; then
        echo "Ошибка: для этой функции требуются 'fzf' и 'psql'." >&2
        return 1
    fi
    local db_user="${1:-postgres}"
    local db_list
    db_list=$(psql -l -t -U "$db_user" 2>/dev/null | cut -d'|' -f1 | sed 's/ //g' | grep -vE '^(template[01]|postgres)$' | grep -v '^$')
    if [ -z "$db_list" ]; then
        echo "Не удалось получить список баз данных или нет доступных баз для бэкапа." >&2
        echo "Возможно, нужно указать правильного пользователя, например: pg_backup my_db_user" >&2
        return 1
    fi
    local db_name
    db_name=$(echo "$db_list" | fzf --height 30% --reverse --prompt="Выберите базу данных для бэкапа: ")
    if [ -z "$db_name" ]; then
        echo "Операция отменена."
        return 0
    fi
    local file_name="${db_name}_$(date +%F_%H-%M-%S).sql.gz"
    echo "Создание дампа базы '${db_name}' (пользователь: ${db_user}) в файл '${file_name}'..."
    pg_dump -Fc -Z 9 -U "${db_user}" "${db_name}" > "${file_name}"
    if [ $? -eq 0 ]; then
        echo "Дамп успешно создан: ${file_name}"
    else
        echo "Ошибка при создании дампа." >&2
        rm -f "${file_name}"
    fi
}

# Интерактивно "убить" один или несколько процессов.
# Требует: fzf
# Пример: fkill
fkill() {
    if ! command_exists "fzf"; then echo "Ошибка: fzf не найден." >&2; return 1; fi
    local show_all=false
    local use_sudo=false
    for arg in "$@"; do
        case $arg in
            -a|--all) show_all=true ;;
            -s|--sudo) use_sudo=true ;;
        esac
    done
    local ps_command
    if [[ "$show_all" = true || $EUID -eq 0 ]]; then
        ps_command="ps -ef"
    else
        ps_command="ps -f -u $USER"
    fi
    local kill_cmd="kill"
    if [[ "$use_sudo" = true || $EUID -eq 0 ]]; then
        kill_cmd="sudo kill"
    fi
    local selection
    selection=$($ps_command | sed 1d | grep -vE "fkill|fzf" | fzf -m --height 50% --reverse --header="Выберите процессы для завершения (Tab для выбора, Enter для подтверждения)")
    if [ -z "$selection" ]; then echo "Операция отменена."; return 0; fi
    local pids_to_kill
    pids_to_kill=$(echo "$selection" | awk '{print $2}')
    echo "Выбраны PID:"
    echo "$pids_to_kill" | sed 's/^/  /'
    read -p "Действие: (k)ill (SIGTERM), (f)orce-kill (SIGKILL) [k]: " action
    local signal=15
    if [[ "$action" == "f" || "$action" == "F" ]]; then
        signal=9
    fi
    echo "Отправка сигнала ${signal} с помощью '$kill_cmd'..."
    local all_killed=true
    for pid in $pids_to_kill; do
        if ! $kill_cmd -"${signal}" "$pid" 2>/dev/null; then
            echo "Не удалось завершить процесс ${pid}." >&2
            all_killed=false
        fi
    done
    if [ "$all_killed" = true ]; then echo "Команда kill успешно отправлена всем выбранным процессам."; fi
}

# Интерактивное управление службами systemd.
# Требует: fzf, systemctl
# Пример: svc (выбрать службу, затем действие)
svc() {
    if ! command_exists "fzf"; then echo "Ошибка: fzf не найден." >&2; return 1; fi
    local unit
    unit=$(systemctl list-units --all --type=service --no-pager --plain | awk '{print $1}' | sed 1d | fzf --height 50% --reverse --prompt="Выберите службу: ")
    if [ -z "$unit" ]; then echo "Операция отменена."; return 0; fi
    read -p "Действие для '${unit}': (s)tatus, (r)estart, st(o)p, st(a)rt [s]: " action
    action=${action:-s}
    case "$action" in
        s) sudo systemctl status "$unit" ;;
        r) sudo systemctl restart "$unit" ;;
        o) sudo systemctl stop "$unit" ;;
        a) sudo systemctl start "$unit" ;;
        *) echo "Неверное действие." >&2 ;;
    esac
}

# Интерактивное управление "спрятанными" изменениями (git stash).
# Требует: fzf
# Пример: gfs (выбрать stash, затем действие)
gfs() {
    if ! command_exists "fzf"; then echo "Ошибка: fzf не найден." >&2; return 1; fi
    local stash
    stash=$(git stash list | fzf --height 40% --reverse --prompt="Выберите stash: " --preview="git show --color=always {1}")
    if [ -z "$stash" ]; then echo "Операция отменена."; return 0; fi
    local stash_ref
    stash_ref=$(echo "$stash" | awk -F: '{print $1}')
    read -p "Действие для '${stash_ref}': (a)pply, (p)op, (d)rop [a]: " action
    action=${action:-a}
    case "$action" in
        a) git stash apply "$stash_ref" ;;
        p) git stash pop "$stash_ref" ;;
        d) git stash drop "$stash_ref" ;;
        *) echo "Неверное действие." >&2 ;;
    esac
}

# Интерактивно выбрать коммиты из другой ветки для cherry-pick.
# Требует: fzf
# Пример: gfc_pick (выбрать ветку, затем коммиты)
gfc_pick() {
    if ! command_exists "fzf"; then echo "Ошибка: fzf не найден." >&2; return 1; fi
    local target_branch
    target_branch=$(git branch --all | fzf --height 30% --reverse --prompt="Выберите ветку-источник: ")
    if [ -z "$target_branch" ]; then echo "Операция отменена."; return 0; fi
    local commits
    commits=$(git log "$target_branch" --oneline --color=always | fzf -m --height 50% --reverse --ansi --prompt="Выберите коммиты для cherry-pick: " --preview="git show --color=always {+1}")
    if [ -n "$commits" ]; then
        local commit_hashes
        commit_hashes=$(echo "$commits" | awk '{print $1}' | tac)
        echo "Выполняется cherry-pick для коммитов:"
        echo "$commit_hashes"
        git cherry-pick $commit_hashes
    fi
}

# Интерактивное подключение к хосту из ~/.ssh/config.
# Требует: fzf
# Пример: sshm
sshm() {
    if ! command_exists "fzf"; then echo "Ошибка: fzf не найден." >&2; return 1; fi
    local host
    host=$(grep -E "^\s*Host\s+" ~/.ssh/config | grep -v '*' | awk '{print $2}' | fzf --height 30% --reverse --prompt="Выберите хост SSH: ")
    if [ -n "$host" ]; then
        echo "Подключение к ${host}..."
        ssh "$host"
    fi
}

# Интерактивный поиск по содержимому файлов с помощью ripgrep и fzf.
# Требует: fzf, ripgrep (rg), bat (опционально)
# Пример: frg "MyApi.Component"
frg() {
    if ! command_exists "rg"; then echo "Ошибка: команда 'ripgrep (rg)' не найдена." >&2; return 1; fi
    local preview_cmd="cat {1}"
    if command_exists "bat"; then
        preview_cmd="bat --color=always --highlight-line {2} {1}"
    fi
    local file_line
    file_line=$(rg --color=always --line-number --no-heading "$1" |
      fzf --ansi \
          --delimiter ':' \
          --preview-window 'up,60%,border-bottom' \
          --preview "$preview_cmd")
    if [ -n "$file_line" ]; then
        local file_to_open; file_to_open=$(echo "$file_line" | cut -d: -f1)
        local line_to_jump; line_to_jump=$(echo "$file_line" | cut -d: -f2)
        ${EDITOR:-nano} +"$line_to_jump" "$file_to_open"
    fi
}

# Найти все комментарии TODO, FIXME, NOTE в проекте.
# Требует: fzf, ripgrep (rg)
# Пример: ftodo
ftodo() {
    if ! command_exists "rg"; then echo "Ошибка: ripgrep (rg) не найден." >&2; return 1; fi
    local preview_cmd="cat {1}"
    if command_exists "bat"; then
        preview_cmd="bat --color=always --highlight-line {2} {1}"
    fi
    rg --line-number --no-heading --color=always -e "(TODO|FIXME|NOTE|HACK):" |
      fzf --ansi \
          --delimiter ':' \
          --preview "$preview_cmd" \
          --preview-window 'up,60%,border-bottom'
}

# Интерактивно переключиться на Pull Request из GitHub.
# Требует: fzf, gh (GitHub CLI)
# Пример: fpr
fpr() {
    if ! command_exists "gh"; then echo "Ошибка: GitHub CLI (gh) не найден." >&2; return 1; fi
    local pr
    pr=$(gh pr list | fzf --height 40% --reverse --header="Выберите Pull Request:")
    if [[ -n "$pr" ]]; then
        local pr_number
        pr_number=$(echo "$pr" | awk '{print $1}')
        gh pr checkout "$pr_number"
    fi
}

# Интерактивно просмотреть открытые порты и связанные с ними процессы.
# Требует: fzf, ss (из iproute2)
# Пример: fports
fports() {
    if ! command_exists "fzf"; then echo "Ошибка: fzf не найден." >&2; return 1; fi
    local port_info
    port_info=$(sudo ss -tulanp | fzf --height 50% --reverse --header="Выберите соединение для просмотра деталей:")
    if [[ -n "$port_info" ]]; then
        local pid
        pid=$(echo "$port_info" | grep -oP 'pid=\K\d+' | head -n 1)
        if [[ -n "$pid" ]]; then
            echo -e "\n\033[1;34m--- Информация о процессе (PID: ${pid}) ---\033[0m"
            ps -o user,pid,ppid,%cpu,%mem,start,etime,cmd -p "$pid"
            read -p "Завершить этот процесс? (y/n): " confirm
            if [[ $confirm == [yY] ]]; then
                sudo kill -9 "$pid"
                echo "Процесс ${pid} завершен."
            fi
        else
            echo "Не удалось определить PID для этого соединения."
        fi
    fi
}

# Интерактивный переход в подкаталог.
# Требует: fzf, и find или fd
# Пример: fcd
fcd() {
    if ! command_exists "fzf"; then
        echo "Ошибка: fzf не найден." >&2
        return 1
    fi
    local dir
    if command_exists "fd"; then
        dir=$(fd --type d --hidden --no-ignore . | fzf --height 50% --reverse --prompt="Перейти в: ")
    else
        dir=$(find . -mindepth 1 -type d 2>/dev/null | sed 's|^\./||' | fzf --height 50% --reverse --prompt="Перейти в: ")
    fi
    if [[ -n "$dir" ]]; then
        if [[ -d "$dir" && -r "$dir" ]]; then
            cd -- "$dir"
        else
            echo "Ошибка: Не удается перейти в '$dir'." >&2
            return 1
        fi
    fi
}

# ==============================================================================
#   РАЗДЕЛ 9: УПРАВЛЕНИЕ ОКРУЖЕНИЕМ 
# ==============================================================================
# Главная функция для управления кастомным окружением Bash.
# Пример: my-bash show aliases
my-bash() {
    local command="$1"
    local component="$2"
    case "$command" in
        show) _my_bash_show "$component" ;;
        help) _my_bash_help "$component" ;;
        *)
            echo "Использование: my-bash <команда> [компонент]"
            echo "Команды:"
            echo "  show   - Показать доступные компоненты (aliases, completions, functions)."
            echo "  help   - Показать детальную справку по компоненту."
            return 1
            ;;
    esac
}

_my_bash_show() {
    case "$1" in
        aliases)
            echo -e "\n\e[1;32mПсевдонимы (aliases)\e[0m"
            echo "Файл: ~/.bash_aliases"
            echo "Для просмотра детальной информации используйте: \`h-alias\` или \`my-bash help aliases\`"
            ;;
        completions)
            echo -e "\n\e[1;32mАвтодополнения (completions)\e[0m"
            if [ -f ~/.bash_completions ]; then
                echo "Файл: ~/.bash_completions"
                echo "Подключенные автодополнения:"
                grep -E '^\s*source' ~/.bash_completions | sed 's/source //' | awk -F'/' '{print "  - " $NF}'
            else
                echo "Файл ~/.bash_completions не найден."
            fi
            ;;
        functions)
            echo -e "\n\e[1;32mФункции (functions)\e[0m"
            echo "Файл: ~/.bash_functions"
            echo "Для просмотра детальной информации используйте: \`h-func\` или \`my-bash help functions\`"
            ;;
        *)
            echo "Доступные компоненты: aliases, completions, functions"
            ;;
    esac
}

_my_bash_help() {
    case "$1" in
        aliases) h-alias ;;
        functions) h-func ;;
        *)
            echo "Использование: my-bash help <компонент>"
            echo "Доступные компоненты для справки: aliases, functions"
            ;;
    esac
}

# ==============================================================================
#   РАЗДЕЛ 10: ПЛАГИНЫ ДЛЯ УПРАВЛЕНИЯ ВЕРСИЯМИ 
# ==============================================================================
# --- Плагин для pyenv ---
# Инициализирует pyenv и включает автопереключение версий.
load_pyenv_plugin() {
    if command_exists "pyenv"; then
        export PYENV_ROOT="${PYENV_ROOT:-$HOME/.pyenv}"
        if [[ -d "$PYENV_ROOT" && ":$PATH:" != *":$PYENV_ROOT/bin:"* ]]; then
            export PATH="$PYENV_ROOT/bin:$PATH"
        fi
        eval "$(pyenv init -)"
        eval "$(pyenv virtualenv-init -)"
    fi
}

# --- Плагин для rbenv ---
# Инициализирует rbenv и добавляет автодополнение.
load_rbenv_plugin() {
    if command_exists "rbenv"; then
        export RBENV_ROOT="${RBENV_ROOT:-$HOME/.rbenv}"
        if [[ -d "$RBENV_ROOT" && ":$PATH:" != *":$RBENV_ROOT/bin:"* ]]; then
            export PATH="$RBENV_ROOT/bin:$PATH"
        fi
        eval "$(rbenv init - bash)"
    fi
}

# ==============================================================================
#   РАЗДЕЛ 11: УЛУЧШЕНИЕ КОМАНДНОЙ СТРОКИ (PROMPT)
# ==============================================================================
# Собирает дополнительную информацию для отображения в PS1.
# Включает: код возврата, информацию о Git, количество фоновых задач.
prompt_info() {
    local exit_code="\[${Green}\]✔\[${Reset}\]"
    if [ "$?" -ne 0 ]; then
        exit_code="\[${Red}\]✘\[${Reset}\]"
    fi
    local git_info=""
    if command_exists "git" && git rev-parse --is-inside-work-tree &>/dev/null; then
        local branch
        branch=$(git rev-parse --abbrev-ref HEAD)
        local dirty=""
        if ! git diff --quiet --ignore-submodules HEAD; then
            dirty=" \[${Red}\]*\[${Reset}\]"
        fi
        git_info=" \[${Magenta}\](git:\[${Cyan}\]${branch}${dirty}\[${Magenta}\])\[${Reset}\]"
    fi
    local jobs_info=""
    if [ "$(jobs -p | wc -l)" -gt 0 ]; then
        jobs_info=" \[${Yellow}\](jobs: $(jobs -p | wc -l))\[${Reset}\]"
    fi
    echo -e "${exit_code}${git_info}${jobs_info} "
}

# ==============================================================================
#   РАЗДЕЛ 12: ПОИСК ПО КОНФИГУРАЦИИ 
# ==============================================================================
# Выполняет поиск по всем конфигурационным файлам, группируя результаты
bsearch() {
    local term="$1"
    if [ -z "$term" ]; then
        echo "Использование: bsearch <поисковый_запрос>"
        echo "Ищет по файлам: .bash_aliases, .bash_functions, .bash_completions, .bash_export"
        return 1
    fi
    declare -A search_locations
    search_locations=(
        ["Псевдонимы (aliases)"]="$HOME/.bash_aliases"
        ["Функции (functions)"]="$HOME/.bash_functions"
        ["Автодополнения (completions)"]="$HOME/.bash_completions"
        ["Переменные (exports)"]="$HOME/.bash_export"
    )
    echo -e "\n🔍 \e[1mРезультаты поиска для \"${term}\":\e[0m\n"
    local found_in_any=false
    for component_name in "Псевдонимы (aliases)" "Функции (functions)" "Автодополнения (completions)" "Переменные (exports)"; do
        local file_path="${search_locations[$component_name]}"
        if [ -f "$file_path" ]; then
            if grep -q -i "$term" "$file_path"; then
                found_in_any=true
                echo -e "✅ \e[1;32mНайдены совпадения в: ${component_name}\e[0m"
                echo -e "   \e[2m(Файл: ${file_path})\e[0m"
                grep --color=always -i -n "$term" "$file_path" | sed 's/^/     /'
                echo ""
            fi
        fi
    done
    if [ "$found_in_any" = false ]; then
        echo "❌ Совпадений не найдено."
    fi
}

# ==============================================================================
#   РАЗДЕЛ 13: ИЗМЕРЕНИЕ ВРЕМЕНИ ВЫПОЛНЕНИЯ КОМАНД 
# ==============================================================================
# --- Механизм preexec ---
preexec() {
    [ -n "$COMP_LINE" ] && return
    [ "$BASH_COMMAND" = "$PROMPT_COMMAND" ] && return
    local preexec_function
    for preexec_function in "${preexec_functions[@]}"; do
        "$preexec_function"
    done
}
precmd() {
    local precmd_function
    for precmd_function in "${precmd_functions[@]}"; do
        "$precmd_function"
    done
}
preexec_functions+=(bash_it_command_duration_start)
precmd_functions+=(bash_it_command_duration_stop)
trap 'preexec' DEBUG

# --- Логика command_duration ---
export BASH_IT_CMD_DURATION_THRESHOLD=5
bash_it_command_duration_start() {
    __bash_it_command_start_time=$(date +%s.%N)
}
bash_it_command_duration_stop() {
    local end_time
    end_time=$(date +%s.%N)
    local start_time=${__bash_it_command_start_time:-0}
    local duration
    duration=$(echo "$end_time - $start_time" | bc -l)
    if (( $(echo "$duration > $BASH_IT_CMD_DURATION_THRESHOLD" | bc -l) )); then
        local formatted_duration
        formatted_duration=$(echo "scale=2; $duration / 1" | bc -l)
        echo -e "\n\e[90m(выполнено за ${formatted_duration}s)\e[0m"
    fi
}

# ==============================================================================
#   РАЗДЕЛ 14: SUDO ПЛАГИН
# ==============================================================================
# Повторяет последнюю команду с sudo при двойном нажатии Esc
sudo-command-line() {
  [[ -z "$READLINE_LINE" ]] && READLINE_LINE="$(history -p '!!')"
  READLINE_LINE="sudo $READLINE_LINE"
  READLINE_POINT=${#READLINE_LINE}
}
# Привязываем функцию к двойному нажатию Escape
bind -x '"\e\e": sudo-command-line'

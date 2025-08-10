#!/bin/bash
# ~/.bash_functions.professional: Профессиональная коллекция shell-функций.
# Этот файл содержит проверенные, безопасные и эффективные функции.

# ==============================================================================
#   РАЗДЕЛ 0: СИСТЕМНЫЕ И СЕССИОННЫЕ ФУНКЦИИ
# ==============================================================================

# update_eternal_history - Сохраняет расширенную историю команд.
# Вызывается перед каждой командой через PROMPT_COMMAND.
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

# sshb - Продвинутая функция SSH для синхронизации окружения.
# БЕЗОПАСНОСТЬ: Используется `mktemp -d` для создания защищенного временного каталога,
# что предотвращает уязвимость типа "race condition".
# НАДЕЖНОСТЬ: Добавлен `trap` для гарантированной очистки временных файлов при выходе.
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
# УЛУЧШЕНО: Добавлены кавычки для поддержки имен файлов с пробелами и проверка на существование файла.
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

# mkcd - Создает директорию и сразу переходит в нее.
mkcd() {
    if [ -z "$1" ]; then
        echo "Использование: mkcd <имя_каталога>" >&2
        return 1
    fi
    mkdir -p -- "$1" && cd -P -- "$1"
}

# -- Раздел 1: Управление файлами и архивами --

# Ищет ФАЙЛ по имени в текущем каталоге и его подкаталогах.
# Использование: ff "имя_файла" (можно использовать маски, например "*.txt").
ff() {
    if [ -z "$1" ]; then
        echo "Использование: ff \"<шаблон_имени_файла>\"" >&2
        return 1
    fi
    find . -type f -name "$1"
}

# Ищет КАТАЛОГ по имени в текущем каталоге и его подкаталогах.
# Использование: fd "имя_папки" (можно использовать маски).
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
    if ! command -v trash-put &> /dev/null; then
        echo "Команда 'trash-put' не найдена. Установите 'trash-cli'." >&2
        return 1
    fi
    if [ $# -eq 0 ]; then
        echo "Использование: trash <файл/каталог> [...]" >&2
        return 1
    fi
    trash-put "$@"
}
# Универсальная функция для извлечения файлов из архивов различных форматов.
# Использование: extract archive.zip archive.tar.gz...
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


# targz - Создает .tar.gz архив.
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

# zipf - Создает .zip архив с исключениями.
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
# --- Сетевые утилиты ---
# doh - DNS-запрос через Google DNS-over-HTTPS (требует jq).
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

# weather - Показывает погоду (требует curl).
weather() {
    local city="${1:-Moscow}"
    curl -s "wttr.in/${city}?format=4"
}

# killg - Завершает процесс по имени, используя pkill.
killg() {
    if [ -z "$1" ]; then
        echo "Использование: killg <имя_процесса>" >&2
        return 1
    fi
    if pkill -fi -9 "$1"; then
        echo "Процессы, содержащие '$1', были завершены."
    else
        echo "Процессы, содержащие '$1', не найдены."
    fi
}
# -- Раздел 2: Навигация и системная информация --

# cl - Переход в каталог и вывод его содержимого.
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
# Использует pydf если доступен, иначе df.
dfh() {
    if command -v pydf &> /dev/null; then
        pydf
    else
        df -Tha --total
    fi
}

# Показывает размер указанного каталога.
# Использование: duh /path/to/directory
duh() {
    if [ -z "$1" ]; then
        du -sh .
    else
        du -sh "$1"
    fi
}

# -- Раздел 3: Сеть и сеанс --

# Выполняет DNS-запрос для указанного типа записи (A, MX, TXT, etc.).
# Использование: digx google.com MX
digx() {
    if [ -z "$1" ]; then
        echo "Использование: digx <домен> [тип_записи]" >&2
        return 1
    fi
    dig +nocmd "$1" "${2:-A}" +noall +answer
}

# Проверяет, открыт ли TCP-порт на хосте.
# Использование: checkport example.com 443
checkport() {
    if nc -z -v -w 2 "$1" "$2" &> /dev/null; then
        echo "Порт $2 на $1 открыт"
    else
        echo "Порт $2 на $1 закрыт"
    fi
}

# Интеллектуальная функция блокировки экрана.
lock() {
    if command -v xdg-screensaver &> /dev/null; then
        xdg-screensaver lock
    elif command -v loginctl &> /dev/null; then
        loginctl lock-session
    elif command -v gnome-screensaver-command &> /dev/null; then
        gnome-screensaver-command -l
    elif command -v xflock4 &> /dev/null; then
        xflock4
    else
        echo "Не найдена команда для блокировки экрана." >&2
        return 1
    fi
}

# -- Раздел 4: Инструменты разработчика --

# Показывает и отслеживает логи для указанного systemd-юнита.
# Использование: jnl-unit nginx.service
jnl-unit() {
    if [ -z "$1" ]; then
        echo "Использование: jnl-unit <имя_юнита>" >&2
        return 1
    fi
    journalctl -u "$1" -f --no-pager
}

# Добавить все, сделать коммит и отправить в удаленный репозиторий.
# Использование: gacp "Мое сообщение о коммите"
gacp() {
    if [ -z "$1" ]; then
        echo "Ошибка: необходимо указать сообщение коммита." >&2
        return 1
    fi
    git add --all && git commit -m "$1" && git push
}

# Создать новую ветку, отправить ее в origin и установить отслеживание.
# Использование: gnewbranch feature/new-thing
gnewbranch() {
    if [ -z "$1" ]; then
        echo "Ошибка: необходимо указать имя новой ветки." >&2
        return 1
    fi
    git checkout -b "$1" && git push -u origin "$1"
}

# Удаляет локальные ветки, которые уже были слиты в основную ветку.
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
# Использование: mkvenv my-project-env
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

# -- Раздел 5: Утилиты --

# transfer - загружает файл или каталог на transfer.sh и возвращает ссылку.
transfer() {
    if [ $# -eq 0 ]; then
        echo "Использование: transfer <файл|каталог> или cat <файл> | transfer <имя_файла>" >&2
        return 1
    fi
    local file="$1"
    local file_name
    if [ -t 0 ]; then
        file_name=$(basename "$file")
        if [ ! -e "$file" ]; then
            echo "Ошибка: '$file' не существует." >&2
            return 1
        fi
        if [ -d "$file" ]; then
            (cd "$(dirname "$file")" && zip -r -q - "$(basename "$file")") |
            curl --progress-bar --upload-file "-" "https://transfer.sh/${file_name}.zip"
        else
            cat "$file" |
            curl --progress-bar --upload-file "-" "https://transfer.sh/$file_name"
        fi
    else
        file_name="$1"
        curl --progress-bar --upload-file "-" "https://transfer.sh/$file_name"
    fi
    echo
}

# extract_column - извлекает указанные столбцы из стандартного ввода.
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

# setup_os_aliases - определяет ОС и создает псевдонимы для управления пакетами.
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

# ==============================================================================
#   РАЗДЕЛ 5: ИНТЕРАКТИВНЫЕ ФУНКЦИИ GIT С ИСПОЛЬЗОВАНИЕМ FZF
# ==============================================================================

# gfb (Git Fuzzy Branch) - интерактивное переключение веток
gfb() {
    if ! command -v fzf &>/dev/null; then echo "Ошибка: fzf не найден." >&2; return 1; fi
    local branches branch
    branches=$(git for-each-ref --count=30 --sort=-committerdate refs/heads/ --format="%(refname:short)") &&
    branch=$(echo "$branches" |
        fzf -d '\t' --preview 'git log --color=always --oneline -n 15 {1}' --reverse) &&
    git checkout "$(echo "$branch" | sed "s/.* //")"
}

# gfl (Git Fuzzy Log) - интерактивный просмотр логов
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

# gfa (Git Fuzzy Add) - интерактивное добавление файлов в индекс
gfa() {
    if ! command -v fzf &>/dev/null; then echo "Ошибка: fzf не найден." >&2; return 1; fi
    local files
    files=$(git -c color.status=always status --short |
        fzf -m --ansi --nth 2.. --preview 'git diff --color=always -- {-1} | sed "s/.* //"' |
        cut -c 4-)
    if [ -n "$files" ]; then
        echo "$files" | xargs git add
        git status -sb
    fi
}

# gfc (Git Fuzzy Checkout-file) - интерактивное восстановление файла из истории
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

# gfd (Git Fuzzy Delete-branch) - интерактивное удаление веток
gfd() {
    if ! command -v fzf &>/dev/null; then echo "Ошибка: fzf не найден." >&2; return 1; fi
    local branches
    branches=$(git branch | grep -vE '^\*|main|master' | fzf -m --preview 'git log --color=always --oneline -n 10 {}')
    if [ -n "$branches" ]; then
        echo "$branches" | xargs git branch -d
    fi
}

# ==============================================================================
#   РАЗДЕЛ 6: ПРОЧИЕ УТИЛИТЫ
# ==============================================================================

# up - Переход вверх по иерархии каталогов.
# Использование: up [количество_уровней]
up() {
    local count=${1:-1}
    local path=""
    for ((i=0; i<count; i++)); do
        path+="../"
    done
    cd "$path"
}

# calc - Калькулятор с поддержкой чисел с плавающей точкой.
calc() {
    if [ -z "$1" ]; then
        echo "Использование: calc \"выражение\"" >&2
        return 1
    fi
    echo "scale=10; $1" | bc -l | sed -E 's/([.0-9]*[1-9])0+$|\.0+$/\1/'
}

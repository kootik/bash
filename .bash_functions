# ~/.bash_functions: Коллекция полезных shell-функций.

# --- "Вечная" история команд ---
# Эта функция вызывается перед каждой командой. Она отправляет последнюю команду
# на удаленный приемник (если он есть) или сохраняет ее в локальный файл.
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

# --- Продвинутая функция SSH ---
# Улучшает работу с SSH, копируя окружение и централизованно собирая историю.
sshb() {
    # ИСПРАВЛЕНО: mktemp -u является более безопасным способом создания уникальных имен.
    local ssh="ssh -S $(mktemp -u ~/.ssh/control-socket.XXXXXXXX)"
    local history_command="rm -f ~/.bash-ssh.history"
    local history_port

    # Проверяем, является ли это вложенным вызовом sshb.
    if [ -r ~/.bash-ssh ]; then
        history_port=$(basename "$(readlink ~/.bash-ssh.history 2>/dev/null)")
    fi

    # Создаем управляющее соединение в фоновом режиме.
    $ssh -fNM "$@" || return $?

    # Если мы находимся во вложенной сессии, пробрасываем порт истории дальше.
    if [ -n "$history_port" ]; then
        local history_remote_port
        history_remote_port="$($ssh -O forward -R 0:127.0.0.1:"$history_port" placeholder)"
        history_command="ln -nsf /dev/tcp/127.0.0.1/$history_remote_port ~/.bash-ssh.history"
    fi

    # ИСПРАВЛЕНО: Теперь мы отправляем полный "пакет" конфигурации, а не один файл.
    # Мы объединяем все необходимые файлы, чтобы воссоздать полное окружение.
    # Порядок важен: .bashrc должен идти первым для корректной работы exec.
    cat ~/.bashrc ~/.bash_export ~/.bash_functions ~/.bash_aliases | $ssh placeholder "${history_command}; cat >~/.bash-ssh"

    # Запускаем интерактивную оболочку на удаленной машине с нашим окружением.
    $ssh "$@" -t 'SHELL=~/.bash-ssh; chmod +x $SHELL; exec bash --rcfile $SHELL -i'

    # Закрываем управляющее соединение при выходе.
    $ssh placeholder -O exit &> /dev/null
}

# --- Утилиты ---

# Создает резервную копию файла с временной меткой.
# УЛУЧШЕНО: Добавлены кавычки для поддержки имен файлов с пробелами.
bak() {
    if [ -z "$1" ]; then echo "Использование: bak <имя_файла>"; return 1; fi
    cp -iv "$1" "$1.$(date +%F_%T)"
}

# Создать директорию и сразу перейти в нее
mkcd() {
    mkdir -p -- "$1" && cd -P -- "$1"
}

# Универсальный распаковщик для различных типов архивов
extract () {
    if [ -f "$1" ] ; then
        case "$1" in
            *.tar.bz2)   tar xvjf "$1"     ;;
            *.tar.gz)    tar xvzf "$1"     ;;
            *.bz2)       bunzip2 "$1"      ;;
            *.rar)       unrar x "$1"      ;;
            *.gz)        gunzip "$1"       ;;
            *.tar)       tar xvf "$1"      ;;
            *.tbz2)      tar xvjf "$1"     ;;
            *.tgz)       tar xvzf "$1"     ;;
            *.zip)       unzip "$1"        ;;
            *.Z)         uncompress "$1"   ;;
            *.7z)        7z x "$1"         ;;
            *)           echo "'$1' не может быть извлечен с помощью extract" ;;
        esac
    else
        echo "'$1' - не является валидным файлом"
    fi
}

# --- Сетевые утилиты ---
# Сделать DNS-запрос через Google DNS-over-HTTPS. Требует `jq`.
doh() {
    if [ -z "$1" ]; then echo "Использование: doh <доменное_имя>"; return 1; fi
    curl -s -H 'accept: application/dns+json' "https://dns.google.com/resolve?name=$1" | jq
}

# Показать информацию о погоде (требует curl)
weather() {
    local city="${1:-Moscow}"
    curl -s "wttr.in/${city}?format=4"
}
# Убить процесс по имени.
# УЛУЧШЕНО: Используется `pkill` вместо небезопасной цепочки ps|grep|awk|xargs.
killg() {
    if [ -z "$1" ]; then echo "Использование: killg <имя_процесса>"; return 1; fi
    pkill -fi -9 "$1" && echo "Процессы, содержащие '$1', были завершены."
}

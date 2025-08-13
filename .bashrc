#!/bin/bash
# ~/.bashrc: Выполняется для не-логин интерактивных оболочек bash.
# ФИНАЛЬНАЯ ВЕРСИЯ, СОВМЕСТИМАЯ С TMUX И SSHB

# ИСПРАВЛЕНИЕ: Обнуляем BASH_ENV, чтобы избежать конфликтов при запуске из tmux.
unset BASH_ENV

# =============================================================================
#  Раздел 1: ГЛАВНЫЙ ЗАЩИТНИК И ОПРЕДЕЛЕНИЕ СТАРТОВЫХ ФУНКЦИЙ
# =============================================================================

# ИЗМЕНЕНО: Улучшенный главный защитник для совместимости с tmux
# Если сессия неинтерактивная (нет $PS1), мы должны выйти.
# Однако, когда tmux запускается, он ИСПОЛНЯЕТ этот скрипт напрямую,
# а не "сорсит" его. В этом случае мы должны позволить скрипту дойти
# до специального обработчика tmux ниже.
if [ -z "$PS1" ]; then
    # Если скрипт был "засорсен" (т.е. не исполнен напрямую), мы можем безопасно выйти.
    if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
        return
    fi
    # Если же скрипт был ИСПОЛНЕН напрямую (как в случае с tmux), мы ничего не делаем
    # и позволяем ему продолжиться до специального обработчика tmux.
fi


# --- ОПРЕДЕЛЕНИЕ КЛЮЧЕВЫХ ФУНКЦИЙ ---
# Эти функции перенесены сюда из .bash_functions, так как они нужны для старта.

# --- Функция для ведения вечной истории (локально и с удаленных хостов) ---
update_eternal_history() {
    local last_command
    # Надежно получаем последнюю команду, убирая начальные пробелы.
    last_command=$(fc -ln -1 | sed 's/^[ \t]*//')

    # Выходим, если команда пустая, является дубликатом предыдущей или это команда history.
    if [[ -z "$last_command" || "$last_command" == "$_ETERNAL_HISTORY_LAST_CMD" || "$last_command" =~ ^history ]]; then
        return
    fi
    # Запоминаем последнюю команду, чтобы избежать дубликатов.
    _ETERNAL_HISTORY_LAST_CMD="$last_command"

    local log_line
    log_line="$(date '+%F %T')\t${USER}@${HOSTNAME}\t${PWD}\t${last_command}"

    # Определяем, куда писать историю: в локальный файл или в канал для SSH.
    local history_target="$HOME/.bash_eternal_history"
    local ssh_pipe="$HOME/.$LOGNAME.bash-ssh.history"

    if [ -p "$ssh_pipe" ]; then
        # ИСПРАВЛЕНО: Запускаем echo в подоболочке с ловушкой для сигнала SIGPIPE,
        # чтобы полностью подавить ошибку "Interrupted system call" при нажатии Ctrl+C.
        (trap '' PIPE; echo -e "$log_line" > "$ssh_pipe") 2>/dev/null || true
    else
        # В обычной локальной сессии просто дописываем в файл.
        local old_umask
        old_umask=$(umask)
        umask 077
        echo -e "$log_line" >> "$history_target"
        umask "$old_umask"
    fi
}

# --- Улучшенная функция для интерактивного подключения с синхронизацией истории ---
sshb() {
    # --- Парсинг аргументов для поддержки флага -i ---
    local identity_opts=()
    local remaining_args=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -i)
                if [[ -n "$2" ]]; then
                    identity_opts+=("-i" "$2")
                    shift 2
                else
                    echo "Ошибка: для опции -i требуется указать путь к файлу." >&2
                    return 1
                fi
                ;;
            *)
                remaining_args+=("$1")
                shift
                ;;
        esac
    done

    if [ ${#remaining_args[@]} -eq 0 ]; then
        echo "Использование: sshb [-i /путь/к/ключу] [user@]hostname [команда]" >&2
        return 1
    fi

    # --- 1. Подготовка и очистка ---
    local tmp_dir
    tmp_dir=$(mktemp -d ~/.ssh/sshb-control.XXXXXXXX)
    if [ -z "$tmp_dir" ]; then
        echo "Не удалось создать временный каталог." >&2
        return 1
    fi
    local listener_pid
    # Гарантированная очистка и остановка фоновых процессов при выходе из функции.
    trap 'rm -rf "$tmp_dir"; [[ -n "$listener_pid" ]] && kill "$listener_pid" &>/dev/null' RETURN

    local control_socket="${tmp_dir}/control-socket"
    local ssh="ssh ${identity_opts[@]} -S ${control_socket}"

    # --- 2. Надёжное определение хоста ---
    local hostname
    hostname=$(ssh "${identity_opts[@]}" -G "${remaining_args[@]}" | awk '/^hostname / { print $2 }')
    if [ -z "$hostname" ]; then
        echo "Ошибка: не удалось определить хост. Проверьте аргументы." >&2
        return 1
    fi

    # --- 3. Сборка "пакета" с окружением ---
    local temp_bundle
    temp_bundle=$(mktemp)
    trap 'rm -rf "$tmp_dir" "$temp_bundle"; [[ -n "$listener_pid" ]] && kill "$listener_pid" &>/dev/null' RETURN

    # Принудительно добавляем шебанг в начало.
    echo '#!/bin/bash' > "$temp_bundle"

    # Собираем окружение.
    local env_files=(
        "$HOME/.bashrc"
        "$HOME/.bash_export"
        "$HOME/.bash_functions"
        "$HOME/.bash_aliases"
    )
    for file in "${env_files[@]}"; do
        [ -r "$file" ] && cat "$file" >> "$temp_bundle"
    done

    # --- 4. Создание мастер-соединения ---
    $ssh -fNM "${remaining_args[@]}" || return 1

    # --- 5. Запуск "слушателя" истории ---
    ($ssh -n "${remaining_args[@]}" 'tail -f $HOME/.$LOGNAME.bash-ssh.history' | while read -r; do echo "$REPLY" >> ~/.bash_eternal_history; done & ) &> /dev/null
    listener_pid=$!

    # --- 6. Подготовка удаленного хоста ---
    cat "$temp_bundle" | $ssh "${remaining_args[@]}" 'cat > $HOME/.$LOGNAME.bash-ssh; [ -p $HOME/.$LOGNAME.bash-ssh.history ] || mkfifo -m 0600 $HOME/.$LOGNAME.bash-ssh.history'
    rm -f "$temp_bundle"

    # --- 7. Запуск интерактивной сессии ---
    $ssh -t "${remaining_args[@]}" 'chmod +x $HOME/.$LOGNAME.bash-ssh; exec bash --rcfile $HOME/.$LOGNAME.bash-ssh -i'

    # --- 8. Закрытие мастер-соединения при выходе ---
    ssh "${identity_opts[@]}" -S "${control_socket}" -O exit "$hostname" &> /dev/null
}

# --- Функция для автоматической настройки псевдонимов пакетных менеджеров ---
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

# =============================================================================
#  Раздел 2: Конфигурация ТОЛЬКО для ИНТЕРАКТИВНЫХ сессий
# =============================================================================

# ФИНАЛЬНОЕ ИСПРАВЛЕНИЕ: Логика для интеграции sshb и tmux.
# ИСПРАВЛЕНО: Проверяем не только SSH_TTY, но и наличие файла, созданного sshb.
# Это предотвращает изменение SHELL на локальной машине.
if [ -n "$SSH_TTY" ] && [ -f "$HOME/.$LOGNAME.bash-ssh" ]; then
    # 1. Принудительно устанавливаем нашу оболочку по умолчанию для этой сессии
    # ИСПРАВЛЕНО: Используем динамическое имя файла, зависящее от пользователя
    export SHELL="$HOME/.$LOGNAME.bash-ssh"

    # 2. Если файл запущен как скрипт (что делает tmux), он перезапускает
    #    bash с правильным конфигом.
    [ "${BASH_SOURCE[0]}" == "${0}" ] && exec bash --rcfile "$SHELL" "$@"
fi

# Загружаем остальные конфигурационные файлы.
[ -f ~/.bash_export ] && . ~/.bash_export
[ -f ~/.bash_functions ] && . ~/.bash_functions
[ -f ~/.bash_aliases ] && . ~/.bash_aliases

# --- Теперь, когда все загружено, можно вызывать команды и функции ---

# Вызываем функцию для создания псевдонимов под текущую ОС
setup_os_aliases

# Добавляем функцию "вечной истории"
[[ "$PROMPT_COMMAND" == *update_eternal_history* ]] || PROMPT_COMMAND="update_eternal_history;$PROMPT_COMMAND"

# Инициализация rbenv/pyenv
type -f rbenv >/dev/null 2>&1 && eval "$(rbenv init -)"
type -f pyenv >/dev/null 2>&1 && eval "$(pyenv init -)"

# --- ИЗМЕНЕНО: Улучшенная настройка SSH Agent ---
# Проверяем наличие любых стандартных приватных ключей (id_rsa, id_ed25519, и т.д.).
# Конструкция `find ... -print -quit | grep -q .` ищет хотя бы один такой файл и завершается.
if find ~/.ssh -type f -name 'id_*' ! -name '*.pub' -print -quit | grep -q .; then
    export SSH_AUTH_SOCK=~/.ssh/agent
    # Запускаем агент, если он еще не запущен
    if ! pgrep -f "$SSH_AUTH_SOCK" >/dev/null; then
        rm -f "$SSH_AUTH_SOCK"
        ssh-agent -a "$SSH_AUTH_SOCK" &>/dev/null
    fi
    # Добавляем ключи, только если в агенте еще нет ни одного ключа,
    # чтобы избежать запроса пароля при каждом открытии терминала.
    if ! ssh-add -l >/dev/null; then
        # Пытаемся добавить все стандартные ключи. Ошибки (например, от зашифрованных ключей) подавляются.
        ssh-add >/dev/null 2>&1
    fi
fi

# Настройка командной строки (Prompt)
if [ -r ~/.byobu/prompt ]; then
    . ~/.byobu/prompt
    PS1=$(sed -e 's/..byobu_prompt_runtime..//' <<<"$PS1")
else
    if [ -x /usr/bin/tput ] && tput setaf 1 >&/dev/null; then
        PS1='\[\e[32m\]\u@\h\[\e[0m\]:\[\e[34m\]\w\[\e[0m\]\$ '
    else
        PS1='\u@\h:\w\$ '
    fi
fi

# Включение bash-completion
if ! shopt -oq posix; then
  if [ -f /usr/share/bash-completion/bash_completion ]; then
    . /usr/share/bash-completion/bash_completion
  elif [ -f /etc/bash_completion ]; then
    . /etc/bash_completion
  fi
fi

# --- ИЗМЕНЕНО: Финальное сообщение о загрузке ---
# Показываем разный вывод для локальной и удаленной sshb сессии.
if [ -n "$SSH_TTY" ] && [ -f "$HOME/.$LOGNAME.bash-ssh" ]; then
    echo ">> Удаленное окружение sshb для ${USER}@${HOSTNAME} успешно загружено."
else
    echo ">> Локальная конфигурация Bash успешно загружена."
fi

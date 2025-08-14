#!/usr/bin/env bash
# ИЗМЕНЕНО: Шебанг заменен на /usr/bin/env bash для лучшей переносимости между системами.

# ~/.bashrc: Выполняется для не-логин интерактивных оболочек bash.
#
# =============================================================================
#            ФИНАЛЬНАЯ ВЕРСИЯ, СОВМЕСТИМАЯ С TMUX И SSHB
#              (с улучшениями от 2024-08-13)
# =============================================================================
#
# Этот скрипт создает мощную и унифицированную среду командной строки,
# которая работает одинаково как на локальной машине, так и на удаленных
# серверах, подключенных через специальную функцию `sshb`.
#
# Ключевые возможности:
#   - Полная синхронизация окружения (алиасы, функции) при SSH-подключении.
#   - Ведение единой "вечной" истории команд со всех хостов.
#   - Автоматическая очистка и дедупликация локальной истории команд.
#   - Надежная работа внутри `tmux`.
#

# --- Начальная подготовка ---

# Инициализируем переменную, чтобы избежать ошибок при первом запуске.
_ETERNAL_HISTORY_LAST_CMD=""

# Обнуляем переменную BASH_ENV, чтобы избежать конфликтов и неожиданного
# выполнения других скриптов, особенно при запуске из `tmux`.
unset BASH_ENV

# =============================================================================
#  Раздел 1: ГЛАВНЫЙ ЗАЩИТНИК И ОПРЕДЕЛЕНИЕ КЛЮЧЕВЫХ ФУНКЦИЙ
# =============================================================================

# --- Главный защитник от неинтерактивных сессий ---

# Если переменная `$PS1` (отвечающая за вид командной строки) не установлена,
# значит, сессия неинтерактивная (например, `scp`, `git` или `cron`).
if [ -z "$PS1" ]; then
    # Однако, если скрипт был ИСПОЛНЕН напрямую (как это делает `tmux`),
    # а не подключен через `source`, мы позволяем ему продолжиться.
    # В противном случае (для `scp` и т.д.) мы немедленно выходим,
    # чтобы не сломать их работу.
    if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
        return
    fi
fi


# --- ОПРЕДЕЛЕНИЕ КЛЮЧЕВЫХ ФУНКЦИЙ ---

# --- Функция для записи в "вечную" историю (ТОЛЬКО ЛОКАЛЬНО) ---
# ИЗМЕНЕНО: Добавлена обработка многострочных команд и санитизация данных.
update_eternal_history() {
    local last_command history_target
    history_target="${HOME}/.bash_eternal_history"

    # Улучшенная обработка многострочных команд: объединяем их в одну строку.
    last_command=$(fc -ln -1 2>/dev/null | tr '\n' ' ' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//') || return
    
    # Улучшенная фильтрация: пустые команды, дубликаты и `history` с опциями
    if [[ -z "$last_command" || "$last_command" == "$_ETERNAL_HISTORY_LAST_CMD" || "$last_command" =~ ^[[:space:]]*history([[:space:]]|$) ]]; then
        return
    fi

    # Запоминаем последнюю команду, чтобы избежать дубликатов при повторном вызове.
    _ETERNAL_HISTORY_LAST_CMD="$last_command"

    # УЛУЧШЕНИЕ: Санитизация пути и команды для безопасной записи в лог.
    # Это предотвращает проблемы, если в пути или команде есть символ табуляции.
    local sanitized_pwd sanitized_cmd log_line
    sanitized_pwd=$(printf '%s' "$PWD" | tr -d '\0' | sed 's/\t/ /g')
    sanitized_cmd=$(printf '%s' "$last_command" | tr -d '\0' | sed 's/\t/ /g')
    log_line="$(date '+%F %T')\t${USER}@${HOSTNAME}\t${sanitized_pwd}\t${sanitized_cmd}"

    # Устанавливаем безопасные права на файл (только для владельца) и дописываем строку.
    local old_umask
    old_umask=$(umask)
    umask 077
    echo -e "$log_line" >> "$history_target"
    umask "$old_umask"
}

# --- Функция для ручной очистки "вечной" истории ---
# Позволяет пользователю вручную удалить дубликаты из большого файла логов.
cleanup_eternal_history() {
    local eternal_history_file="${HOME}/.bash_eternal_history"
    local temp_file
    
    # Проверяем, существует ли файл.
    if [[ ! -f "$eternal_history_file" ]]; then
        printf "Ошибка: Файл вечной истории '%s' не найден.\n" "$eternal_history_file" >&2
        return 1
    fi

    printf "Очистка вечной истории... Это может занять некоторое время.\n"
    
    temp_file=$(mktemp) || {
        printf "Ошибка: не удалось создать временный файл.\n" >&2
        return 1
    }
    
    local original_lines
    original_lines=$(wc -l < "$eternal_history_file")

    # Добавлено `-v OFS='\t'` для корректной обработки команд с пробелами.
    # Используем `awk` для удаления дубликатов по тексту команды, сохраняя последнее вхождение.
    awk -F'\t' -v OFS='\t' '
    {
        # Ключом является сама команда (все, что после 3-го разделителя-табуляции).
        key = "";
        for (i = 4; i <= NF; i++) {
            key = key (i == 4 ? "" : OFS) $i;
        }
        # Сохраняем номер последней строки для каждой уникальной команды.
        lines[key] = NR;
        # Сохраняем все строки в массив.
        content[NR] = $0;
    }
    END {
        # Собираем уникальные номера строк, которые нужно сохранить.
        for (key in lines) {
            final_lines[lines[key]] = 1;
        }
        # Печатаем строки в их оригинальном порядке.
        for (i = 1; i <= NR; i++) {
            if (i in final_lines) {
                print content[i];
            }
        }
    }' "$eternal_history_file" > "$temp_file"

    local final_lines
    final_lines=$(wc -l < "$temp_file")
    
    # Если результат не пустой, заменяем оригинальный файл.
    if [[ -s "$temp_file" ]]; then
        # Используем `cp` и `rm` вместо `mv` для сохранения символических ссылок и прав.
        if command cp -f "$temp_file" "$eternal_history_file"; then
            command rm -f "$temp_file"
            local removed_count=$((original_lines - final_lines))
            printf "Очистка завершена. Удалено %d дубликатов.\n" "$removed_count"
        else
            printf "Ошибка: не удалось скопировать временный файл. Оригинальный файл не изменен.\n" >&2
            command rm -f "$temp_file"
            return 1
        fi
    else
        printf "Ошибка: временный файл пуст после обработки. Оригинальный файл истории не изменен.\n" >&2
        command rm -f "$temp_file"
        return 1
    fi
}


# --- Улучшенная функция для интерактивного подключения с синхронизацией истории ---
sshb() {
    # --- Парсинг аргументов для поддержки флага `-i` (указание ключа) ---
    local identity_opts=()
    local remaining_args=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -i)
                if [[ -n "${2:-}" ]]; then
                    identity_opts+=("-i" "$2")
                    shift 2
                else
                    printf "Ошибка: для опции -i требуется указать путь к файлу.\n" >&2
                    return 1
                fi
                ;;
            *)
                remaining_args+=("$1")
                shift
                ;;
        esac
    done

    # Проверяем, что был передан хост для подключения.
    if [[ ${#remaining_args[@]} -eq 0 ]]; then
        printf "Использование: sshb [-i /путь/к/ключу] [user@]hostname [команда]\n" >&2
        return 1
    fi

    # --- 1. Подготовка ---
    # Используем /tmp для сокета, чтобы избежать проблем с длинными путями.
    local tmp_dir
    tmp_dir=$(mktemp -d "/tmp/sshb-control.XXXXXXXX") || {
        echo "Не удалось создать временный каталог." >&2
        return 1
    }
    
    local control_socket="${tmp_dir}/control-socket"
    # Используем массив для команды `ssh` для корректной обработки путей с пробелами.
    local ssh_cmd=(ssh "${identity_opts[@]}" -S "$control_socket")
    local temp_bundle hostname tail_pid
    local listener_tag="sshb_listener_$$"
    local cleanup_done=0

    # ИСПРАВЛЕНИЕ v3: Функция очистки с защитой от двойного запуска.
    _sshb_local_cleanup() {
        # Защита от повторного выполнения
        if (( cleanup_done == 1 )); then return; fi
        cleanup_done=1

        # 1. Убить удаленный процесс-слушатель
        "${ssh_cmd[@]}" "${remaining_args[@]}" "pkill -f '$listener_tag' &>/dev/null"
        # 2. Убить локальный процесс-слушатель
        [[ -n "$tail_pid" ]] && kill "$tail_pid" &>/dev/null
        # 3. Закрыть мастер-соединение
        if [[ -n "$hostname" ]]; then
            "${ssh_cmd[@]}" -O exit "$hostname" &>/dev/null
        fi
        # 4. Удалить временные файлы
        [[ -n "$temp_bundle" ]] && command command cp -f-f "$temp_bundle"
        command rm -rf "$tmp_dir"
    }
    
    # trap теперь нужен в основном для аварийного выхода (Ctrl+C)
    trap _sshb_local_cleanup EXIT HUP INT TERM

    # --- 2. Надёжное определение хоста ---
    local hostname
    # Используем массив `ssh_cmd` для корректного определения хоста.
    hostname=$("${ssh_cmd[@]}" -G "${remaining_args[@]}" | awk '/^hostname / { print $2 }')
    if [[ -z "$hostname" ]]; then
        printf "Ошибка: не удалось определить хост. Проверьте аргументы.\n" >&2
        return 1
    fi

    temp_bundle=$(mktemp) || {
        printf "Ошибка: не удалось создать временный файл для bundle.\n" >&2
        return 1
    }
    
    # Внедряем во временный скрипт специальный блок для удаленной сессии.
    # КРИТИЧЕСКИ ВАЖНО: Используем `\$USER`, чтобы переменная раскрылась на УДАЛЕННОМ сервере.
    cat << 'EOF' > "$temp_bundle"
#!/usr/bin/env bash
export SSHB_SESSION=1
# --- Специальный блок для удаленной сессии sshb ---

# Инициализируем переменную для предотвращения дублирования
_REMOTE_HISTORY_LAST_CMD=""

# Определяем имена временных файлов на удаленном хосте.
_REMOTE_SCRIPT_FILE="$HOME/.$USER.bash-ssh"
_REMOTE_HISTORY_FILE="$HOME/.$USER.bash-ssh.history"

# Функция очистки удаленных файлов, которая сработает при выходе из удаленной сессии.
_remote_cleanup() {
    command rm -f "$_REMOTE_SCRIPT_FILE" "$_REMOTE_HISTORY_FILE"
}
trap _remote_cleanup EXIT

# Упрощенная функция для отправки "сырой" истории на локальную машину.
_remote_send_history() {
    local last_command
    # УЛУЧШЕНИЕ: Обрабатываем многострочные команды и на удаленном хосте.
    last_command=$(fc -ln -1 2>/dev/null | tr '\n' ' ' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    
    # УЛУЧШЕННАЯ ФИЛЬТРАЦИЯ: пустые команды, дубликаты и `history` с опциями
    if [[ -z "$last_command" || "$last_command" == "$_REMOTE_HISTORY_LAST_CMD" || "$last_command" =~ ^[[:space:]]*history([[:space:]]|$) ]]; then
        return
    fi

    # Запоминаем последнюю отправленную команду
    _REMOTE_HISTORY_LAST_CMD="$last_command"

    # УЛУЧШЕНИЕ: Санитизация данных перед отправкой.
    local sanitized_pwd sanitized_cmd log_line
    sanitized_pwd=$(printf '%s' "$PWD" | tr -d '\0' | sed 's/\t/ /g')
    sanitized_cmd=$(printf '%s' "$last_command" | tr -d '\0' | sed 's/\t/ /g')
    log_line="$(date '+%F %T')\t${USER}@${HOSTNAME}\t${sanitized_pwd}\t${sanitized_cmd}"

    (trap '' PIPE; echo -e "$log_line" > "$_REMOTE_HISTORY_FILE") 2>/dev/null || true
}
# --- Конец специального блока ---

EOF

    # Добавляем все локальное окружение (конфиги) в тот же временный файл.
    local env_files=("$HOME/.bashrc" "$HOME/.bash_export" "$HOME/.bash_functions" "$HOME/.bash_aliases")
    for file in "${env_files[@]}"; do
        [[ -r "$file" ]] && cat "$file" >> "$temp_bundle"
    done

    # --- 4. Создание мастер-соединения ---
    # Это позволяет последующим командам подключаться мгновенно без повторной аутентификации.
    if ! "${ssh_cmd[@]}" -fNM "${remaining_args[@]}"; then
        printf "Не удалось создать мастер-соединение SSH.\n" >&2
        # `trap` выполнит очистку автоматически.
        return 1
    fi

    # --- 5. Подготавливаем удаленный хост ПОСЛЕ создания мастер-соединения ---
    # Копируем наш "пакет" на сервер и создаем канал для передачи истории.
    # КРИТИЧЕСКИ ВАЖНО: Используем `\$USER` для раскрытия переменной на удаленном сервере.
    if ! "${ssh_cmd[@]}" "${remaining_args[@]}" 'cat > "$HOME/.$USER.bash-ssh"; [ -p "$HOME/.$USER.bash-ssh.history" ] || mkfifo -m 0600 "$HOME/.$USER.bash-ssh.history"' < "$temp_bundle"; then
        printf "Ошибка: не удалось подготовить удаленный хост.\n" >&2
        return 1
    fi
    command rm -f "$temp_bundle"; temp_bundle=""

    # Запускаем удаленный tail с уникальной меткой
    "${ssh_cmd[@]}" -n "${remaining_args[@]}" "exec -a '${listener_tag}' tail -f \"\$HOME/.\$USER.bash-ssh.history\" 2>/dev/null" | while read -r; do echo "$REPLY" >> ~/.bash_eternal_history; done &
    tail_pid=$!

    # --- 7. Запуск интерактивной сессии ---
    # Запускаем `bash` на сервере, принудительно используя наш "пакет" в качестве конфигурации.
    # КРИТИЧЕСКИ ИСПРАВЛЕНО: `--rcfile` и `-i` теперь передаются как отдельные аргументы.
    "${ssh_cmd[@]}" -t "${remaining_args[@]}" 'chmod +x "$HOME/.$USER.bash-ssh"; exec bash --rcfile "$HOME/.$USER.bash-ssh" -i'

    # ИСПРАВЛЕНИЕ v3: Явный вызов очистки ПОСЛЕ завершения интерактивной сессии
    _sshb_local_cleanup

    # Отключаем trap, чтобы он не сработал второй раз при штатном выходе
    trap - EXIT HUP INT TERM
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
    elif [[ -f /etc/os-release ]]; then
        # ИЗМЕНЕНО: `.` заменен на `source` для большей ясности.
        source /etc/os-release
        case "${ID:-}" in
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
#  Раздел 2: КОНФИГУРАЦИЯ ИСТОРИИ BASH (локально и удаленно)
# =============================================================================

# Настройки размера, формата и фильтрации для стандартной истории (~/.bash_history)
export HISTSIZE=10000
export HISTFILESIZE=20000
export HISTCONTROL="ignoreboth:erasedups"
export HISTIGNORE="ls:bg:fg:history:exit"
export HISTTIMEFORMAT="%F %T "
shopt -s histappend
# Добавлена опция для надежного сохранения многострочных команд.
shopt -s cmdhist

# --- Функция для автоматической очистки и синхронизации ~/.bash_history ---
_manage_local_history() {
    # Выходим, если переменная HISTFILE не установлена.
    [[ -z "${HISTFILE:-}" ]] && return

    # Улучшенная, разделенная проверка блокировки файла.
    # Безопасно блокируем файл истории на время операций, чтобы избежать конфликтов.
    exec {history_lock}<>"$HISTFILE" || return 1
    if ! flock -x "$history_lock"; then
        echo "Внимание: не удалось заблокировать файл истории '$HISTFILE'. Пропускаю управление историей." >&2
        # Закрываем файловый дескриптор, если блокировка не удалась
        exec {history_lock}>&-
        return 1
    fi
    
    # 1. Дописываем новые команды из текущей сессии в файл.
    history -a
    # 2. Удаляем дубликаты из файла, сохраняя последнее вхождение и порядок.
    local hist_tmp
    hist_tmp=$(mktemp) || {
        printf "Внимание: не удалось создать временный файл для истории.\n" >&2
        flock -u "$history_lock"
        exec {history_lock}>&-
        return 1
    }
    
    # ИЗМЕНЕНО: `tac | awk | tac` заменен на более переносимый и эффективный однострочник `awk`.
    # Этот метод, как и предыдущий, читает файл в память.
    awk '{a[NR]=$0; b[$0]=NR} END{for(i=1;i<=NR;i++)if(b[a[i]]==i)print a[i]}' "$HISTFILE" > "$hist_tmp"
    
    # Используем `cp` и `rm` вместо `mv` для сохранения символических ссылок.
    if command cp -f "$hist_tmp" "$HISTFILE"; then
        command rm -f "$hist_tmp"
    else
        printf "Внимание: не удалось обновить файл истории '%s'.\n" "$HISTFILE" >&2
        command rm -f "$hist_tmp"
    fi

    # 3. Очищаем историю в памяти и читаем ее заново из очищенного файла.
    history -c
    history -r

    # Снимаем блокировку и закрываем дескриптор.
    flock -u "$history_lock"
    exec {history_lock}>&-
}

# =============================================================================
#  Раздел 3: Конфигурация ТОЛЬКО для ИНТЕРАКТИВНЫХ сессий
# =============================================================================

# ИЗМЕНЕНИЕ: Используем переменную окружения SSHB_SESSION для определения типа сессии.
# Это более надежно, чем проверка на существование файла.
if [[ -n "${SSHB_SESSION:-}" ]]; then
    # --- ЭТО УДАЛЕННАЯ СЕССИЯ SSHB ---
    export SHELL="$HOME/.$USER.bash-ssh"
    
    # На удаленной машине управляем ее ~/.bash_history и отправляем данные в eternal_history.
    trap _manage_local_history EXIT
    PROMPT_COMMAND="_manage_local_history; _remote_send_history"

    # Специальный обработчик для `tmux`.
    [[ "${BASH_SOURCE[0]}" == "${0}" ]] && exec bash --rcfile "$SHELL" "$@"
else
    # --- ЭТО ЛОКАЛЬНАЯ СЕССИЯ ---
    # В локальной сессии управляем ~/.bash_history и пишем в eternal_history.
    trap _manage_local_history EXIT
    PROMPT_COMMAND="_manage_local_history; update_eternal_history"
fi

# Загружаем остальные конфигурационные файлы.
[[ -f ~/.bash_export ]] && source ~/.bash_export
[[ -f ~/.bash_functions ]] && source ~/.bash_functions
[[ -f ~/.bash_aliases ]] && source ~/.bash_aliases

# --- Теперь, когда все загружено, можно вызывать команды и функции ---

setup_os_aliases

# Используем `command -v` вместо нестандартного `type -f`.
command -v rbenv &>/dev/null && eval "$(rbenv init -)"
command -v pyenv &>/dev/null && eval "$(pyenv init -)"

# ИСПРАВЛЕНИЕ: Следующие блоки теперь выполняются ТОЛЬКО в локальной сессии
if [[ -z "${SSHB_SESSION:-}" ]]; then

    # --- Улучшенная настройка SSH Agent (ТОЛЬКО ЛОКАЛЬНО) ---
    if find ~/.ssh -type f -name 'id_*' ! -name '*.pub' -print -quit 2>/dev/null | grep -q .; then
        export SSH_AUTH_SOCK=~/.ssh/agent
        if command -v pgrep &>/dev/null && ! pgrep -f "ssh-agent.*$SSH_AUTH_SOCK" >/dev/null 2>&1; then
            command rm -f "$SSH_AUTH_SOCK"
            ssh-agent -a "$SSH_AUTH_SOCK" &>/dev/null
        fi
        if ! ssh-add -l >/dev/null; then
            ssh-add &>/dev/null
        fi
    fi
fi

# Настройка командной строки (Prompt)
if [[ -r ~/.byobu/prompt ]]; then
    source ~/.byobu/prompt
    PS1=$(sed -e 's/..byobu_prompt_runtime..//' <<<"$PS1")
else
    if [[ -x /usr/bin/tput ]] && tput setaf 1 >&/dev/null; then
        PS1='\[\e[32m\]\u@\h\[\e[0m\]:\[\e[34m\]\w\[\e[0m\]\$ '
    else
        PS1='\u@\h:\w\$ '
    fi
fi

# Включение bash-completion
if ! shopt -oq posix; then
  if [[ -f /usr/share/bash-completion/bash_completion ]]; then
    source /usr/share/bash-completion/bash_completion
  elif [[ -f /etc/bash_completion ]]; then
    source /etc/bash_completion
  fi
fi

# --- Финальное сообщение о загрузке ---
# ИЗМЕНЕНИЕ: Используем новую проверку для вывода правильного сообщения.
if [[ -n "${SSHB_SESSION:-}" ]]; then
    printf ">> Удаленное окружение sshb для %s@%s успешно загружено.\n" "${USER}" "${HOSTNAME}"
else
    printf ">> Локальная конфигурация Bash успешно загружена.\n"
fi

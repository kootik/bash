#!/usr/bin/env bash
# ~/.bashrc: Выполняется для не-логин интерактивных оболочек bash.
#
# =============================================================================
#            ФИНАЛЬНАЯ ВЕРСИЯ, СОВМЕСТИМАЯ С TMUX И SSHB
# =============================================================================

# --- Начальная подготовка ---
_ETERNAL_HISTORY_LAST_CMD=""
unset BASH_ENV

# =============================================================================
#  Раздел 1: ГЛАВНЫЙ ЗАЩИТНИК И ОПРЕДЕЛЕНИЕ КЛЮЧЕВЫХ ФУНКЦИЙ
# =============================================================================

# --- Главный защитник от неинтерактивных сессий ---
if [ -z "$PS1" ]; then
    if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
        return
    fi
fi

# --- ОПРЕДЕЛЕНИЕ КЛЮЧЕВЫХ ФУНКЦИЙ ---

# --- Функция для записи в "вечную" историю (ТОЛЬКО ЛОКАЛЬНО) ---
update_eternal_history() {
    local last_command history_target
    history_target="${HOME}/.bash_eternal_history"
    last_command=$(fc -ln -1 2>/dev/null | tr '\n' ' ' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//') || return
    if [[ -z "$last_command" || "$last_command" == "$_ETERNAL_HISTORY_LAST_CMD" || "$last_command" =~ ^[[:space:]]*history([[:space:]]|$) ]]; then
        return
    fi
    _ETERNAL_HISTORY_LAST_CMD="$last_command"
    local sanitized_pwd sanitized_cmd log_line
    sanitized_pwd=$(printf '%s' "$PWD" | tr -d '\0' | sed 's/\t/ /g')
    sanitized_cmd=$(printf '%s' "$last_command" | tr -d '\0' | sed 's/\t/ /g')
    log_line="$(date '+%F %T')\t${USER}@${HOSTNAME}\t${sanitized_pwd}\t${sanitized_cmd}"
    local old_umask
    old_umask=$(umask)
    umask 077
    echo -e "$log_line" >> "$history_target"
    umask "$old_umask"
}

# --- Функция для ручной очистки "вечной" истории ---
cleanup_eternal_history() {
    local eternal_history_file="${HOME}/.bash_eternal_history"
    local temp_file
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
    awk -F'\t' -v OFS='\t' '
    {
        key = "";
        for (i = 4; i <= NF; i++) {
            key = key (i == 4 ? "" : OFS) $i;
        }
        lines[key] = NR;
        content[NR] = $0;
    }
    END {
        for (key in lines) {
            final_lines[lines[key]] = 1;
        }
        for (i = 1; i <= NR; i++) {
            if (i in final_lines) {
                print content[i];
            }
        }
    }' "$eternal_history_file" > "$temp_file"
    local final_lines
    final_lines=$(wc -l < "$temp_file")
    if [[ -s "$temp_file" ]]; then
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
    if [[ ${#remaining_args[@]} -eq 0 ]]; then
        printf "Использование: sshb [-i /путь/к/ключу] [user@]hostname [команда]\n" >&2
        return 1
    fi
    local tmp_dir
    tmp_dir=$(mktemp -d "/tmp/sshb-control.XXXXXXXX") || {
        echo "Не удалось создать временный каталог." >&2
        return 1
    }
    local control_socket="${tmp_dir}/control-socket"
    local ssh_cmd=(ssh "${identity_opts[@]}" -S "$control_socket")
    local temp_bundle hostname tail_pid
    local listener_tag="sshb_listener_$$"
    local cleanup_done=0
    _sshb_local_cleanup() {
        if (( cleanup_done == 1 )); then return; fi
        cleanup_done=1
        "${ssh_cmd[@]}" "${remaining_args[@]}" "pkill -f '$listener_tag' &>/dev/null"
        [[ -n "$tail_pid" ]] && kill "$tail_pid" &>/dev/null
        if [[ -n "$hostname" ]]; then
            "${ssh_cmd[@]}" -O exit "$hostname" &>/dev/null
        fi
        [[ -n "$temp_bundle" ]] && command rm -f "$temp_bundle"
        command rm -rf "$tmp_dir"
    }
    trap _sshb_local_cleanup EXIT HUP INT TERM
    local hostname
    hostname=$("${ssh_cmd[@]}" -G "${remaining_args[@]}" | awk '/^hostname / { print $2 }')
    if [[ -z "$hostname" ]]; then
        printf "Ошибка: не удалось определить хост. Проверьте аргументы.\n" >&2
        return 1
    fi
    temp_bundle=$(mktemp) || {
        printf "Ошибка: не удалось создать временный файл для bundle.\n" >&2
        return 1
    }
    cat << 'EOF' > "$temp_bundle"
#!/usr/bin/env bash
export SSHB_SESSION=1
# --- Специальный блок для удаленной сессии sshb ---
_REMOTE_HISTORY_LAST_CMD=""
_REMOTE_SCRIPT_FILE="$HOME/.$USER.bash-ssh"
_REMOTE_HISTORY_FILE="$HOME/.$USER.bash-ssh.history"
_remote_cleanup() {
    command rm -f "$_REMOTE_SCRIPT_FILE" "$_REMOTE_HISTORY_FILE"
}
trap _remote_cleanup EXIT
_remote_send_history() {
    local last_command
    last_command=$(fc -ln -1 2>/dev/null | tr '\n' ' ' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    if [[ -z "$last_command" || "$last_command" == "$_REMOTE_HISTORY_LAST_CMD" || "$last_command" =~ ^[[:space:]]*history([[:space:]]|$) ]]; then
        return
    fi
    _REMOTE_HISTORY_LAST_CMD="$last_command"
    local sanitized_pwd sanitized_cmd log_line
    sanitized_pwd=$(printf '%s' "$PWD" | tr -d '\0' | sed 's/\t/ /g')
    sanitized_cmd=$(printf '%s' "$last_command" | tr -d '\0' | sed 's/\t/ /g')
    log_line="$(date '+%F %T')\t${USER}@${HOSTNAME}\t${sanitized_pwd}\t${sanitized_cmd}"
    (trap '' PIPE; echo -e "$log_line" > "$_REMOTE_HISTORY_FILE") 2>/dev/null || true
}
# --- Конец специального блока ---
EOF
    local env_files=("$HOME/.bashrc" "$HOME/.bash_export" "$HOME/.bash_functions" "$HOME/.bash_aliases" "$HOME/.bash_completions")
    for file in "${env_files[@]}"; do
        [[ -r "$file" ]] && cat "$file" >> "$temp_bundle"
    done
    if ! "${ssh_cmd[@]}" -fNM "${remaining_args[@]}"; then
        printf "Не удалось создать мастер-соединение SSH.\n" >&2
        return 1
    fi
    if ! "${ssh_cmd[@]}" "${remaining_args[@]}" 'cat > "$HOME/.$USER.bash-ssh"; [ -p "$HOME/.$USER.bash-ssh.history" ] || mkfifo -m 0600 "$HOME/.$USER.bash-ssh.history"' < "$temp_bundle"; then
        printf "Ошибка: не удалось подготовить удаленный хост.\n" >&2
        return 1
    fi
    command rm -f "$temp_bundle"; temp_bundle=""
    "${ssh_cmd[@]}" -n "${remaining_args[@]}" "exec -a '${listener_tag}' tail -f \"\$HOME/.\$USER.bash-ssh.history\" 2>/dev/null" | while read -r; do echo "$REPLY" >> ~/.bash_eternal_history; done &
    tail_pid=$!
    "${ssh_cmd[@]}" -t "${remaining_args[@]}" 'chmod +x "$HOME/.$USER.bash-ssh"; exec bash --rcfile "$HOME/.$USER.bash-ssh" -i'
    _sshb_local_cleanup
    trap - EXIT HUP INT TERM
}

# =============================================================================
#  Раздел 2: КОНФИГУРАЦИЯ ИСТОРИИ BASH (локально и удаленно)
# =============================================================================
export HISTSIZE=10000
export HISTFILESIZE=20000
export HISTCONTROL="ignoreboth:erasedups"
export HISTIGNORE="ls:bg:fg:history:exit:bask" # Добавлен bask в игнор
export HISTTIMEFORMAT="%F %T "
shopt -s histappend
shopt -s cmdhist

_manage_local_history() {
    [[ -z "${HISTFILE:-}" ]] && return
    exec {history_lock}<>"$HISTFILE" || return 1
    if ! flock -x "$history_lock"; then
        echo "Внимание: не удалось заблокировать файл истории '$HISTFILE'. Пропускаю управление историей." >&2
        exec {history_lock}>&-
        return 1
    fi
    history -a
    local hist_tmp
    hist_tmp=$(mktemp) || {
        printf "Внимание: не удалось создать временный файл для истории.\n" >&2
        flock -u "$history_lock"
        exec {history_lock}>&-
        return 1
    }
    awk '{a[NR]=$0; b[$0]=NR} END{for(i=1;i<=NR;i++)if(b[a[i]]==i)print a[i]}' "$HISTFILE" > "$hist_tmp"
    if command cp -f "$hist_tmp" "$HISTFILE"; then
        command rm -f "$hist_tmp"
    else
        printf "Внимание: не удалось обновить файл истории '%s'.\n" "$HISTFILE" >&2
        command rm -f "$hist_tmp"
    fi
    history -c
    history -r
    flock -u "$history_lock"
    exec {history_lock}>&-
}

# =============================================================================
#  Раздел 3: Конфигурация ТОЛЬКО для ИНТЕРАКТИВНЫХ сессий
# =============================================================================
if [[ -n "${SSHB_SESSION:-}" ]]; then
    # --- ЭТО УДАЛЕННАЯ СЕССИЯ SSHB ---
    export SHELL="$HOME/.$USER.bash-ssh"
    trap _manage_local_history EXIT
    PROMPT_COMMAND="precmd; _manage_local_history; _remote_send_history"
    [[ "${BASH_SOURCE[0]}" == "${0}" ]] && exec bash --rcfile "$SHELL" "$@"
else
    # --- ЭТО ЛОКАЛЬНАЯ СЕССИЯ ---
    trap _manage_local_history EXIT
    PROMPT_COMMAND="precmd; _manage_local_history; update_eternal_history"
fi

# --- Загрузка конфигурационных файлов ---
[[ -f ~/.bash_export ]] && source ~/.bash_export
[[ -f ~/.bash_functions ]] && source ~/.bash_functions
[[ -f ~/.bash_aliases ]] && source ~/.bash_aliases
[[ -f ~/.bash_completions ]] && source ~/.bash_completions

# --- Настройка командной строки (Prompt) ---
if [[ -r ~/.byobu/prompt ]]; then
    source ~/.byobu/prompt
    PS1=$(sed -e 's/..byobu_prompt_runtime..//' <<<"$PS1")
else
    # Используем новые цветовые переменные и функцию prompt_info
    PS1='$(prompt_info)\[${BGreen}\]\u@\h\[${Reset}\]:\[${BBlue}\]\w\[${Reset}\]\$ '
fi

# --- Включение стандартного bash-completion ---
if ! shopt -oq posix; then
  if [[ -f /usr/share/bash-completion/bash_completion ]]; then
    source /usr/share/bash-completion/bash_completion
  elif [[ -f /etc/bash_completion ]]; then
    source /etc/bash_completion
  fi
fi

# --- Интеграция плагина history-substring-search ---
# Поиск по истории по подстроке стрелками вверх/вниз
bind '"\e[A": history-search-backward'
bind '"\e[B": history-search-forward'

# --- Финальная инициализация ---
# Вызываем функции, которые должны быть выполнены после загрузки всех компонентов.
setup_os_aliases
load_pyenv_plugin
load_rbenv_plugin
load_direnv_plugin      # <-- НОВАЯ СТРОКА
load_smart_nav_plugin   # <-- НОВАЯ СТРОКА

# --- Финальное сообщение о загрузке ---
if [[ -n "${SSHB_SESSION:-}" ]]; then
    printf ">> Удаленное окружение sshb для %s@%s успешно загружено.\n" "${USER}" "${HOSTNAME}"
else
     printf ">> Локальная конфигурация Bash успешно загружена.\n"
fi

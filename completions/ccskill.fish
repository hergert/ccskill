# Fish completions for ccskill

# Disable file completions
complete -c ccskill -f

# Commands
complete -c ccskill -n "__fish_use_subcommand" -a "list" -d "Show available skills"
complete -c ccskill -n "__fish_use_subcommand" -a "status" -d "Show installed skills + updates"
complete -c ccskill -n "__fish_use_subcommand" -a "info" -d "Show skill details"
complete -c ccskill -n "__fish_use_subcommand" -a "add" -d "Add skill to project"
complete -c ccskill -n "__fish_use_subcommand" -a "remove" -d "Remove skill from project"
complete -c ccskill -n "__fish_use_subcommand" -a "update" -d "Update skills"
complete -c ccskill -n "__fish_use_subcommand" -a "sync" -d "Pull latest from git"
complete -c ccskill -n "__fish_use_subcommand" -a "init" -d "Initialize registry"
complete -c ccskill -n "__fish_use_subcommand" -a "help" -d "Show help"

# Skill name completions for commands that take a skill argument
function __fish_ccskill_available_skills
    set -l registry "$HOME/.skills"
    test -d "$registry" || return
    for dir in $registry/*/
        set -l skill (basename $dir)
        test -f "$registry/$skill/SKILL.md" && echo $skill
    end
end

function __fish_ccskill_installed_skills
    set -l skills ".claude/skills"
    test -d "$skills" || return
    for dir in $skills/*/
        set -l skill (basename $dir)
        test -f "$skills/$skill/SKILL.md" && echo $skill
    end
end

# Complete skill names for info/add (available skills)
complete -c ccskill -n "__fish_seen_subcommand_from info add" -a "(__fish_ccskill_available_skills)"

# Complete skill names for remove/update (installed skills)
complete -c ccskill -n "__fish_seen_subcommand_from remove update" -a "(__fish_ccskill_installed_skills)"

# --yes flag
complete -c ccskill -s y -l yes -d "Skip confirmations"

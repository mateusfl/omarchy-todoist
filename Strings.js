// UI copy for the Todoist plugin, keyed by language tag. New language: add
// a dictionary below and a { value, label } entry in LANGUAGES.
//
// No Qt/QML here, same as Model.js, so this can run under node too.

var DEFAULT_LANGUAGE = "en-US"

var LANGUAGES = [
  { value: "en-US", label: "English" },
  { value: "pt-BR", label: "Português (Brasil)" }
]

var DICTS = {
  "en-US": {
    tooltipRefresh: "Refresh",
    tooltipLogout: "Log out",
    tooltipSettings: "Settings",
    tooltipConfigureToken: "Set up your Todoist token",
    tooltipTasksDue: "task(s) overdue or due today",
    tooltipNoTasksToday: "No tasks due today",
    tabInbox: "Inbox",
    tabToday: "Today",
    tabUpcoming: "Upcoming",
    emptyInbox: "Inbox is empty 🎉",
    emptyToday: "No overdue or due-today tasks 🎉",
    emptyUpcoming: "No overdue, due-today, or upcoming (7-day) tasks 🎉",
    cliMissing: "The `td` CLI wasn't found. Install it with: npm install -g @doist/todoist-cli",
    loginButtonIdle: "Log in with browser",
    loginButtonBusy: "Opening the browser…",
    tokenHint: "or paste a personal API token (Todoist → Settings → Integrations → Developer):",
    tokenPlaceholder: "Todoist token",
    saveButtonIdle: "Save",
    savingEllipsis: "…",
    tokenError: "Couldn't save that token. Double-check it and try again.",
    quickAddPlaceholder: "Add a task… (e.g. Meeting tomorrow p1 #Work)",
    sectionOverdue: "OVERDUE",
    sectionToday: "TODAY",
    sectionUpcoming: "NEXT 7 DAYS",
    dueOverdue: "Overdue",
    dueToday: "Today",
    dueTomorrow: "Tomorrow",
    settingsTitle: "Settings",
    languageLabel: "Language"
  },
  "pt-BR": {
    tooltipRefresh: "Atualizar",
    tooltipLogout: "Sair",
    tooltipSettings: "Configurações",
    tooltipConfigureToken: "Configurar token do Todoist",
    tooltipTasksDue: "tarefa(s) atrasada(s) ou para hoje",
    tooltipNoTasksToday: "Nenhuma tarefa pendente hoje",
    tabInbox: "Inbox",
    tabToday: "Hoje",
    tabUpcoming: "Próximos",
    emptyInbox: "Inbox vazia 🎉",
    emptyToday: "Nenhuma tarefa atrasada ou para hoje 🎉",
    emptyUpcoming: "Nenhuma tarefa atrasada, para hoje, ou nos próximos 7 dias 🎉",
    cliMissing: "CLI `td` não encontrada. Instale com: npm install -g @doist/todoist-cli",
    loginButtonIdle: "Entrar com o navegador",
    loginButtonBusy: "Abrindo o navegador…",
    tokenHint: "ou cole um token de API pessoal (Todoist → Configurações → Integrações → Developer):",
    tokenPlaceholder: "Token do Todoist",
    saveButtonIdle: "Salvar",
    savingEllipsis: "…",
    tokenError: "Não foi possível salvar esse token. Confira e tente novamente.",
    quickAddPlaceholder: "Adicionar tarefa… (ex: Reunião amanhã p1 #Trabalho)",
    sectionOverdue: "ATRASADAS",
    sectionToday: "HOJE",
    sectionUpcoming: "PRÓXIMOS 7 DIAS",
    dueOverdue: "Atrasada",
    dueToday: "Hoje",
    dueTomorrow: "Amanhã",
    settingsTitle: "Configurações",
    languageLabel: "Idioma"
  }
}

function dict(lang) {
  return DICTS[lang] || DICTS[DEFAULT_LANGUAGE]
}

function t(lang, key) {
  var value = dict(lang)[key]
  return value === undefined ? key : value
}

if (typeof module !== "undefined") {
  module.exports = {
    DEFAULT_LANGUAGE: DEFAULT_LANGUAGE,
    LANGUAGES: LANGUAGES,
    t: t
  }
}

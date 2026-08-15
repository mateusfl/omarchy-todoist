// Pure helpers for the Todoist bar widget: parsing the `td` CLI's JSON
// output, Todoist's own color vocabulary (priority flags, project colors),
// and due-date grouping. Kept side-effect free so it's easy to reason about
// independently of the QML that drives the `td` process.
//
// `td` (the official Doist CLI, https://github.com/Doist/todoist-cli) does
// not nest a `project` object in task output even with `--full` — tasks
// carry `projectId`, resolved here against a separately-fetched project
// list. `pick()`'s multi-key fallback exists for fields (`due`, `priority`)
// that plausibly differ between `td`'s versions rather than fields we've
// seen vary in practice.

function pick(obj, keys) {
  if (!obj) return undefined
  for (var i = 0; i < keys.length; i++) {
    var v = obj[keys[i]]
    if (v !== undefined && v !== null && v !== "") return v
  }
  return undefined
}

// `td`'s CLI-facing priority is "p1".."p4" (p1 = most urgent); the
// underlying API field is the inverted 1-4 integer. Accept either.
function toPriorityNumber(value) {
  if (typeof value === "number" && isFinite(value)) return value
  var s = String(value === undefined || value === null ? "" : value).trim().toLowerCase()
  var m = s.match(/^p([1-4])$/)
  if (m) return 5 - parseInt(m[1], 10)
  var n = parseInt(s, 10)
  return isNaN(n) ? 1 : n
}

// `td auth status --json` / any `td` command replies with
// {"error":{"code":"NO_TOKEN",...}} when no credential is stored yet.
function isAuthErrorResponse(parsed) {
  return !!(parsed && parsed.error)
}

function parseJson(raw) {
  try {
    return JSON.parse(String(raw || ""))
  } catch (e) {
    return null
  }
}

// `td ... --json` list commands return either a bare array or
// { results/tasks/projects: [...], next_cursor }.
function parseListResponse(raw) {
  var data = parseJson(raw)
  if (!data) return []
  if (Array.isArray(data)) return data
  if (Array.isArray(data.results)) return data.results
  if (Array.isArray(data.tasks)) return data.tasks
  if (Array.isArray(data.projects)) return data.projects
  if (Array.isArray(data.items)) return data.items
  return []
}

// Todoist's own priority-flag palette (p1..p4).
function priorityColor(priorityNumber) {
  if (priorityNumber === 4) return "#d1453b"
  if (priorityNumber === 3) return "#eb8909"
  if (priorityNumber === 2) return "#246fe0"
  return ""
}

// Todoist's named project/label color palette, mapped to the hex values
// Todoist itself renders them as. Unknown names fall back to the theme
// accent color at the call site.
var PROJECT_COLORS = {
  berry_red: "#b8256f",
  red: "#db4035",
  orange: "#ff9933",
  yellow: "#fad000",
  olive_green: "#afb83b",
  lime_green: "#7ecc49",
  green: "#299438",
  mint_green: "#6accbc",
  teal: "#158fad",
  sky_blue: "#14aaf5",
  light_blue: "#96c3eb",
  blue: "#4073ff",
  grape: "#884dff",
  violet: "#af38eb",
  lavender: "#eb96eb",
  magenta: "#e05194",
  salmon: "#ff8d85",
  charcoal: "#808080",
  grey: "#b8b8b8",
  taupe: "#ccac93"
}

function projectColorHex(colorName, fallback) {
  var hex = PROJECT_COLORS[String(colorName || "").toLowerCase()]
  return hex || fallback || ""
}

function buildProjectIndex(projects) {
  var index = {}
  for (var i = 0; i < projects.length; i++) {
    var p = projects[i]
    var id = pick(p, ["id"])
    if (id === undefined) continue
    index[String(id)] = {
      name: pick(p, ["name"]) || "",
      color: projectColorHex(pick(p, ["color"]), "")
    }
  }
  return index
}

function dateKeyFromDate(date) {
  return Qt.formatDate(date, "yyyy-MM-dd")
}

// Bucket a task by its due date against "today": overdue / today / upcoming.
// Tasks with no due date are "upcoming" so they still surface rather than
// vanishing.
function classifyDue(dueDateStr, todayKey) {
  if (!dueDateStr) return "upcoming"
  if (dueDateStr < todayKey) return "overdue"
  if (dueDateStr === todayKey) return "today"
  return "upcoming"
}

// `dueLabels` supplies the three words this can't compute itself
// (overdue/today/tomorrow) so the caller's chosen UI language decides them,
// keeping this file free of any single language's strings. Defaults to
// English, matching Strings.js's DEFAULT_LANGUAGE.
var DEFAULT_DUE_LABELS = { overdue: "Overdue", today: "Today", tomorrow: "Tomorrow" }

function formatDueLabel(due, todayKey, tomorrowKey, dueLabels) {
  var labels = dueLabels || DEFAULT_DUE_LABELS
  var dateRaw = pick(due, ["date", "day"])
  if (!dateRaw) return ""
  var dateStr = String(dateRaw).slice(0, 10)
  if (dateStr < todayKey) return labels.overdue
  var datetime = pick(due, ["datetime"])
  if (dateStr === todayKey) return datetime ? formatTime(datetime) : labels.today
  if (dateStr === tomorrowKey) return labels.tomorrow
  var d = new Date(dateStr + "T12:00:00")
  if (isNaN(d.getTime())) return pick(due, ["string"]) || dateStr
  return Qt.formatDate(d, "d MMM")
}

function formatTime(datetimeStr) {
  var d = new Date(datetimeStr)
  if (isNaN(d.getTime())) return ""
  return Qt.formatTime(d, "HH:mm")
}

// Normalize one task from `td task list --full --json` into what the panel
// renders, resolving its project against the inline object first and the
// separately-fetched project index as a fallback.
function normalizeTask(task, projectIndex, todayKey, tomorrowKey, dueLabels) {
  var id = pick(task, ["id"])
  var due = pick(task, ["due"]) || null
  var dueDateRaw = due ? pick(due, ["date", "day"]) : pick(task, ["dueDate", "due_date"])
  var dueDate = dueDateRaw ? String(dueDateRaw).slice(0, 10) : ""

  var projectObj = pick(task, ["project"])
  var projectId = projectObj ? pick(projectObj, ["id"]) : pick(task, ["projectId", "project_id"])
  var inlineName = projectObj ? pick(projectObj, ["name"]) : pick(task, ["projectName", "project_name"])
  var inlineColor = projectObj ? projectColorHex(pick(projectObj, ["color"]), "") : ""
  var indexed = projectId !== undefined ? projectIndex[String(projectId)] : null

  var priorityNumber = toPriorityNumber(pick(task, ["priority"]))

  return {
    id: String(id),
    content: pick(task, ["content", "title", "text"]) || "",
    url: pick(task, ["url", "webUrl", "web_url"]) || "",
    priority: priorityNumber,
    priorityColor: priorityColor(priorityNumber),
    dueDate: dueDate,
    dueLabel: due ? formatDueLabel(due, todayKey, tomorrowKey, dueLabels) : "",
    bucket: classifyDue(dueDate, todayKey),
    projectName: inlineName || (indexed ? indexed.name : ""),
    projectColor: inlineColor || (indexed ? indexed.color : "")
  }
}

function taskSortKey(task) {
  // Undated tasks sort after dated ones within the same bucket.
  var datePart = task.dueDate || "9999-99-99"
  var priorityPart = 4 - task.priority
  return datePart + "-" + priorityPart
}

// The panel's tab bar: each entry names the `td` subcommand (+args) that
// produces its list. All three accept the same --json/--full/--show-urls/
// --all suffix, appended by the caller. Labels/empty-text live in
// Strings.js (keyed "tab<Id>"/"empty<Id>", id capitalized) so this stays
// free of any single language's strings.
var TABS = [
  { id: "inbox", command: ["inbox"] },
  { id: "today", command: ["today"] },
  { id: "upcoming", command: ["task", "list", "--filter", "overdue | today | 7 days"] }
]

function tabDefinitions() {
  return TABS
}

function tabById(id) {
  for (var i = 0; i < TABS.length; i++) if (TABS[i].id === id) return TABS[i]
  return TABS[0]
}

function buildGroups(rawTasks, rawProjects, todayKey, tomorrowKey, dueLabels) {
  var projectIndex = buildProjectIndex(rawProjects || [])
  var normalized = []
  for (var i = 0; i < rawTasks.length; i++) {
    var t = rawTasks[i]
    if (!t || pick(t, ["id"]) === undefined) continue
    normalized.push(normalizeTask(t, projectIndex, todayKey, tomorrowKey, dueLabels))
  }

  var groups = { overdue: [], today: [], upcoming: [] }
  for (var j = 0; j < normalized.length; j++) {
    groups[normalized[j].bucket].push(normalized[j])
  }
  var sorter = function(a, b) { return taskSortKey(a) < taskSortKey(b) ? -1 : (taskSortKey(a) > taskSortKey(b) ? 1 : 0) }
  groups.overdue.sort(sorter)
  groups.today.sort(sorter)
  groups.upcoming.sort(sorter)
  return groups
}

if (typeof module !== "undefined") {
  module.exports = {
    pick: pick,
    toPriorityNumber: toPriorityNumber,
    isAuthErrorResponse: isAuthErrorResponse,
    parseJson: parseJson,
    parseListResponse: parseListResponse,
    tabDefinitions: tabDefinitions,
    tabById: tabById,
    priorityColor: priorityColor,
    projectColorHex: projectColorHex,
    buildProjectIndex: buildProjectIndex,
    dateKeyFromDate: dateKeyFromDate,
    classifyDue: classifyDue,
    formatDueLabel: formatDueLabel,
    formatTime: formatTime,
    normalizeTask: normalizeTask,
    taskSortKey: taskSortKey,
    buildGroups: buildGroups
  }
}

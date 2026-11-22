/**
 * El Completo: renderiza "Esta semana en la cocina" en la portada.
 * Fuente unica: data/menu-semanal.json; nunca modifica recetas individuales.
 * Semana: lunes a domingo en America/Edmonton. Sin seleccion valida => aviso.
 * Se ejecuta antes de la compilacion de Quartz (y en un despliegue programado
 * cada lunes, para que caduque cualquier menu de la semana anterior).
 */
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const content = path.join(root, "content");
const recipesRoot = path.join(content, "01 - Recetas");
const homepage = path.join(content, "index.md");
const menuPath = path.join(root, "data", "menu-semanal.json");
const begin = "<!-- EL_COMPLETO_MENU_SEMANAL_START -->";
const end = "<!-- EL_COMPLETO_MENU_SEMANAL_END -->";
const fallbackImage = "El Completo - Icono.png";
const timezone = "America/Edmonton";

function zonedToday(date = new Date()) {
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone: timezone, year: "numeric", month: "2-digit", day: "2-digit",
  }).formatToParts(date);
  const field = (name) => parts.find((p) => p.type === name)?.value;
  return `${field("year")}-${field("month")}-${field("day")}`;
}
function mondayOf(isoDate) {
  const instant = new Date(`${isoDate}T12:00:00Z`);
  if (!Number.isFinite(instant.getTime()) || instant.toISOString().slice(0, 10) !== isoDate) {
    throw new Error(`Fecha ISO invalida: ${isoDate}`);
  }
  const diff = (instant.getUTCDay() + 6) % 7;
  instant.setUTCDate(instant.getUTCDate() - diff);
  return instant.toISOString().slice(0, 10);
}
function weekEnd(weekStart) {
  const value = new Date(`${weekStart}T12:00:00Z`);
  value.setUTCDate(value.getUTCDate() + 6);
  return value.toISOString().slice(0, 10);
}
function formatWeek(start) {
  const format = (date) => new Intl.DateTimeFormat("es-CL", {
    timeZone: "UTC", day: "numeric", month: "long", year: "numeric",
  }).format(new Date(`${date}T12:00:00Z`));
  return `Semana del ${format(start)} al ${format(weekEnd(start))}`;
}
function yamlValue(meta, key) {
  const m = meta.match(new RegExp(`^${key}:\\s*(.+?)\\s*$`, "m"));
  return m ? m[1].trim().replace(/^['"]|['"]$/g, "") : "";
}
function metadata(source, filename) {
  const found = /^\uFEFF?---\r?\n([\s\S]*?)\r?\n---(?:\r?\n|$)/.exec(source);
  if (!found) throw new Error(`Falta frontmatter YAML en ${filename}`);
  return found[1];
}
function permittedImage(relative) {
  if (!relative) return null;
  const normalized = relative.replaceAll("\\", "/");
  if (!normalized.startsWith("03 - Recursos/Fotografías/") || normalized.includes("..")) return null;
  if (/[\[\]|<>]/.test(normalized)) return null;
  if (!fs.existsSync(path.join(content, ...normalized.split("/")))) return null;
  return path.posix.basename(normalized);
}
function photo(meta, source) {
  const field = permittedImage(yamlValue(meta, "foto"));
  if (field) return field;
  for (const [, raw] of source.matchAll(/!\[\[([^\]\|]+\.(?:webp|png|jpe?g))(?:\|[^\]]+)?\]\]/gi)) {
    const name = path.posix.basename(raw.replaceAll("\\", "/"));
    for (const folder of [
      "03 - Recursos/Fotografías",
      "03 - Recursos/Fotografías/Ilustraciones IA",
      "03 - Recursos/Fotografías/Propias aprobadas",
    ]) {
      const result = permittedImage(`${folder}/${name}`);
      if (result) return result;
    }
  }
  const icon = path.join(content, "03 - Recursos", "Identidad visual", fallbackImage);
  if (!fs.existsSync(icon)) throw new Error("Falta imagen de respaldo publica de El Completo.");
  return fallbackImage;
}
function readRecipes() {
  const all = new Map();
  for (const category of fs.readdirSync(recipesRoot, { withFileTypes: true })) {
    if (!category.isDirectory()) continue;
    for (const item of fs.readdirSync(path.join(recipesRoot, category.name), { withFileTypes: true })) {
      if (!item.isFile() || item.name === "index.md" || !item.name.endsWith(".md")) continue;
      const name = path.basename(item.name, ".md");
      const source = fs.readFileSync(path.join(recipesRoot, category.name, item.name), "utf8");
      const meta = metadata(source, item.name);
      if (yamlValue(meta, "draft").toLowerCase() === "true") continue;
      if (/[\[\]|<>\r\n]/.test(name + category.name)) throw new Error(`Nombre no seguro: ${item.name}`);
      const entry = { name, category: category.name, image: photo(meta, source) };
      if (all.has(name)) throw new Error(`Nombre de receta duplicado entre categorias: ${name}`);
      all.set(name, entry);
    }
  }
  return all;
}
const menu = JSON.parse(fs.readFileSync(menuPath, "utf8"));
if (!Array.isArray(menu.recetas) || menu.recetas.length > 5) {
  throw new Error("menu-semanal.json debe incluir un arreglo de 0 a 5 recetas.");
}
if (menu.recetas.some((r) => typeof r !== "string" || !r.trim())) {
  throw new Error("Cada receta del menu debe ser un nombre no vacio.");
}
if (new Set(menu.recetas).size !== menu.recetas.length) throw new Error("Recetas repetidas en el menu.");
if (menu.semana_inicio !== null && (typeof menu.semana_inicio !== "string" ||
  mondayOf(menu.semana_inicio) !== menu.semana_inicio)) {
  throw new Error("semana_inicio debe ser null o una fecha YYYY-MM-DD que corresponda a lunes.");
}
if (menu.recetas.length && !menu.semana_inicio) {
  throw new Error("Hay recetas seleccionadas, pero falta semana_inicio.");
}
const all = readRecipes();
const selected = menu.recetas.map((name) => {
  const recipe = all.get(name);
  if (!recipe) throw new Error(`La receta seleccionada no existe o esta en borrador: ${name}`);
  return recipe;
});
const today = zonedToday();
const currentMonday = mondayOf(today);
const nextMondayDate = new Date(`${currentMonday}T12:00:00Z`);
nextMondayDate.setUTCDate(nextMondayDate.getUTCDate() + 7);
const nextMonday = nextMondayDate.toISOString().slice(0, 10);
// El domingo se puede mostrar ya el menu de la semana que comienza manana:
// es cuando normalmente se decide que cocinar y se prepara la compra.
const isSunday = new Date(`${today}T12:00:00Z`).getUTCDay() === 0;
const showing = selected.length > 0 &&
  (menu.semana_inicio === currentMonday || (isSunday && menu.semana_inicio === nextMonday));
const cards = showing ? selected.map((r) =>
  `- ![[${r.image}]]  \n  [[${r.name}]] <span class="el-completo-menu-categoria">${r.category}</span>`
).join("\n") : "_Todavía no hay recetas seleccionadas para esta semana._";
const description = showing ? `\n\n*${formatWeek(menu.semana_inicio)}*` : "";
const page = fs.readFileSync(homepage, "utf8");
const start = page.indexOf(begin);
const finish = page.indexOf(end);
if (start < 0 || finish < start || page.indexOf(begin, start + begin.length) >= 0) {
  throw new Error("Faltan marcadores unicos del menu semanal en content/index.md.");
}
const next = page.slice(0, start + begin.length) +
  `\n\n## Esta semana en la cocina\n\n${cards}${description}\n\n` +
  page.slice(finish);
if (next !== page) fs.writeFileSync(homepage, next, "utf8");
console.log(showing
  ? `El Completo: menu semanal ${menu.semana_inicio} con ${selected.length} recetas.`
  : "El Completo: portada sin recetas elegidas para la semana actual.");

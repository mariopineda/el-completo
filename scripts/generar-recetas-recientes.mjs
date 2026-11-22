/**
 * El Completo: actualiza las cinco recetas recientes antes de compilar Quartz.
 * Se ordenan por su primera incorporacion a Git (no por fecha de modificacion).
 * Requisitos: Node 18+, Git disponible, checkout con historial completo.
 */
import fs from "node:fs";
import path from "node:path";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const content = path.join(root, "content");
const recipeRoot = path.join(content, "01 - Recetas");
const homepage = path.join(content, "index.md");
const begin = "<!-- EL_COMPLETO_RECIENTES_START -->";
const end = "<!-- EL_COMPLETO_RECIENTES_END -->";
const fallbackImage = "El Completo - Icono.png";

function getFrontmatter(source, filename) {
  const match = /^\uFEFF?---\r?\n([\s\S]*?)\r?\n---(?:\r?\n|$)/.exec(source);
  if (!match) throw new Error("Falta YAML frontmatter: " + filename);
  return match[1];
}
function getValue(frontmatter, key) {
  const pattern = new RegExp("^" + key + ":[ \\t]*([^\\r\\n]*)$", "m");
  const match = frontmatter.match(pattern);
  return match ? match[1].trim().replace(/^[\'"]|[\'"]$/g, "").trim() : "";
}
function existingImage(rel) {
  if (!rel) return null;
  const normalized = rel.replaceAll("\\", "/");
  if (!normalized.startsWith("03 - Recursos/Fotografías/")) return null;
  if (normalized.includes("..") || normalized.includes("|") || normalized.includes("]")) return null;
  return fs.existsSync(path.join(content, ...normalized.split("/")))
    ? path.posix.basename(normalized) : null;
}
function findImage(frontmatter, source) {
  const image = existingImage(getValue(frontmatter, "foto"));
  if (image) return image;
  // Recetas originales como el burrito usan una imagen en el cuerpo.
  // Solo se incluyen imagenes presentes en el repositorio publico.
  for (const match of source.matchAll(/!\[\[([^\]\|]+\.(?:webp|png|jpe?g))(?:\|[^\]]+)?\]\]/gi)) {
    const filename = path.posix.basename(match[1].replaceAll("\\", "/"));
    if (/[\[\]\|]/.test(filename)) continue;
    for (const folder of [
      "03 - Recursos/Fotografías",
      "03 - Recursos/Fotografías/Ilustraciones IA",
      "03 - Recursos/Fotografías/Propias aprobadas",
    ]) {
      const candidate = existingImage(folder + "/" + filename);
      if (candidate) return candidate;
    }
  }
  if (!fs.existsSync(path.join(content, "03 - Recursos", "Identidad visual", fallbackImage))) {
    throw new Error("Falta el icono publico de respaldo.");
  }
  return fallbackImage;
}
function dateFirstAdded(relativePath, frontmatter) {
  try {
    const output = execFileSync(
      "git",
      ["log", "--diff-filter=A", "--format=%ct", "--", relativePath],
      { cwd: root, encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] }
    ).trim();
    if (output) {
      const newestAddition = Number(output.split(/\r?\n/)[0]);
      if (Number.isFinite(newestAddition) && newestAddition > 0) return newestAddition;
    }
  } catch { /* La fuente puede ejecutarse fuera de Git. */ }
  const fallbackDate = getValue(frontmatter, "fecha_de_ingreso");
  if (fallbackDate) {
    const timestamp = Date.parse(fallbackDate + "T00:00:00Z");
    if (Number.isFinite(timestamp)) return Math.floor(timestamp / 1000);
  }
  return 0;
}

if (!fs.existsSync(recipeRoot)) throw new Error("No existe el directorio de recetas.");
const results = [];
for (const category of fs.readdirSync(recipeRoot, { withFileTypes: true })) {
  if (!category.isDirectory()) continue;
  const categoryPath = path.join(recipeRoot, category.name);
  for (const item of fs.readdirSync(categoryPath, { withFileTypes: true })) {
    if (!item.isFile() || !item.name.endsWith(".md") || item.name === "index.md") continue;
    const title = path.basename(item.name, ".md");
    if (/[\[\]\|<>\r\n]/.test(title) || /[\[\]\|<>\r\n]/.test(category.name)) {
      throw new Error("Nombre incompatible con la galeria: " + item.name);
    }
    const source = fs.readFileSync(path.join(categoryPath, item.name), "utf8");
    const meta = getFrontmatter(source, item.name);
    if (getValue(meta, "draft").toLowerCase() === "true") continue;
    const relative = path.posix.join("content", "01 - Recetas", category.name, item.name);
    results.push({
      title,
      category: category.name,
      image: findImage(meta, source),
      added: dateFirstAdded(relative, meta),
    });
  }
}
if (results.length < 5) throw new Error("Se necesitan al menos cinco recetas publicables.");

results.sort((a, b) => b.added - a.added
  || a.title.localeCompare(b.title, "es", { sensitivity: "base" }));
const latest = results.slice(0, 5);
const cards = latest.map((r) => {
  return "- ![[" + r.image + "]]  \n  [[" + r.title + "]] " +
    '<span class="el-completo-reciente-categoria">' + r.category + "</span>";
}).join("\n");
let original = fs.readFileSync(homepage, "utf8");
let start = original.indexOf(begin);
let finish = original.indexOf(end);
// Un exportador local antiguo puede reconstruir la portada sin marcadores.
// En ese caso, se restablece la sección antes de compilar el sitio.
if (start < 0 && finish < 0 && original.includes("[[01 - Recetas/index|")) {
  original = original.trimEnd() + "\n\n" + begin + "\n\n" + end + "\n";
  start = original.indexOf(begin);
  finish = original.indexOf(end);
}
if (start < 0 || finish < start || original.indexOf(begin, start + begin.length) >= 0) {
  throw new Error("Portada sin estructura válida de recetas recientes.");
}
const rendered = original.slice(0, start + begin.length) +
  "\n\n## Recetas recientes\n\n" + cards + "\n\n" +
  original.slice(finish);
if (rendered !== original) fs.writeFileSync(homepage, rendered, "utf8");
console.log("El Completo: cinco recetas recientes incluidas en la portada.");
for (const r of latest) console.log(" - " + r.title + " (" + r.category + ")");

import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import { execSync } from "child_process";
import { writeFileSync, mkdirSync } from "fs";
import { join } from "path";
function run(cmd, cwd) {
    try {
        return execSync(cmd, {
            encoding: "utf-8",
            cwd,
            timeout: 30000,
        }).trim();
    }
    catch (e) {
        const err = e;
        throw new Error(err.stderr || err.message || "Command failed");
    }
}
function writeModuleContent(name, content) {
    const repoPath = run("ai-inst repo path");
    const modulePath = join(repoPath, "modules", `${name}.md`);
    writeFileSync(modulePath, content, "utf-8");
}
function writeSkillContent(name, content) {
    const repoPath = run("ai-inst repo path");
    const skillDir = join(repoPath, "skills", name);
    const skillPath = join(skillDir, "SKILL.md");
    mkdirSync(skillDir, { recursive: true });
    writeFileSync(skillPath, content, "utf-8");
}
const server = new McpServer({
    name: "ai-inst",
    version: "0.1.0",
});
// ─── Tools ───────────────────────────────────────────────────────────────────
server.tool("list_modules", "List all available instruction modules", {}, async () => {
    const output = run("ai-inst list");
    return { content: [{ type: "text", text: output || "No modules found." }] };
});
server.tool("read_module", "Read the content of a module", { name: z.string().describe("Module name") }, async ({ name }) => {
    const output = run(`ai-inst show ${name}`);
    return { content: [{ type: "text", text: output }] };
});
server.tool("create_module", "Create a new instruction module", {
    name: z.string().describe("Module name"),
    content: z.string().describe("Module content (markdown)"),
}, async ({ name, content }) => {
    const repoPath = run("ai-inst repo path");
    const modulePath = join(repoPath, "modules", `${name}.md`);
    writeFileSync(modulePath, content, "utf-8");
    run(`cd "${repoPath}" && git add -A && git commit -m "add module: ${name}"`);
    return { content: [{ type: "text", text: `Module '${name}' created.` }] };
});
server.tool("update_module", "Update the content of an existing module", {
    name: z.string().describe("Module name"),
    content: z.string().describe("New module content (markdown)"),
}, async ({ name, content }) => {
    // Verify it exists
    run(`ai-inst show ${name}`);
    writeModuleContent(name, content);
    const repoPath = run("ai-inst repo path");
    run(`cd "${repoPath}" && git add -A && git commit -m "update module: ${name}"`);
    return { content: [{ type: "text", text: `Module '${name}' updated.` }] };
});
server.tool("delete_module", "Delete a module", { name: z.string().describe("Module name") }, async ({ name }) => {
    run(`ai-inst rm ${name}`);
    return { content: [{ type: "text", text: `Module '${name}' deleted.` }] };
});
server.tool("list_project_modules", "List modules configured for a project", { project_path: z.string().describe("Absolute path to the project directory") }, async ({ project_path }) => {
    const output = run("ai-inst project status", project_path);
    return { content: [{ type: "text", text: output }] };
});
server.tool("add_project_module", "Add modules to a project", {
    project_path: z.string().describe("Absolute path to the project directory"),
    modules: z.array(z.string()).describe("Module names to add"),
}, async ({ project_path, modules }) => {
    const output = run(`ai-inst project add ${modules.join(" ")}`, project_path);
    return { content: [{ type: "text", text: output }] };
});
server.tool("remove_project_module", "Remove modules from a project", {
    project_path: z.string().describe("Absolute path to the project directory"),
    modules: z.array(z.string()).describe("Module names to remove"),
}, async ({ project_path, modules }) => {
    const output = run(`ai-inst project rm ${modules.join(" ")}`, project_path);
    return { content: [{ type: "text", text: output }] };
});
server.tool("build", "Build instruction files for a project", { project_path: z.string().describe("Absolute path to the project directory") }, async ({ project_path }) => {
    const output = run("ai-inst build", project_path);
    return { content: [{ type: "text", text: output }] };
});
// ─── Skill tools ─────────────────────────────────────────────────────────────
server.tool("list_skills", "List all available skills", {}, async () => {
    const output = run("ai-inst skill list");
    return { content: [{ type: "text", text: output || "No skills found." }] };
});
server.tool("read_skill", "Read the content of a skill", { name: z.string().describe("Skill name") }, async ({ name }) => {
    const output = run(`ai-inst skill show ${name}`);
    return { content: [{ type: "text", text: output }] };
});
server.tool("create_skill", "Create a new skill", {
    name: z.string().describe("Skill name"),
    content: z.string().describe("SKILL.md content (markdown with YAML frontmatter)"),
}, async ({ name, content }) => {
    writeSkillContent(name, content);
    const repoPath = run("ai-inst repo path");
    run(`cd "${repoPath}" && git add -A && git commit -m "add skill: ${name}"`);
    return { content: [{ type: "text", text: `Skill '${name}' created.` }] };
});
server.tool("update_skill", "Update the content of an existing skill", {
    name: z.string().describe("Skill name"),
    content: z.string().describe("New SKILL.md content (markdown with YAML frontmatter)"),
}, async ({ name, content }) => {
    run(`ai-inst skill show ${name}`);
    writeSkillContent(name, content);
    const repoPath = run("ai-inst repo path");
    run(`cd "${repoPath}" && git add -A && git commit -m "update skill: ${name}"`);
    return { content: [{ type: "text", text: `Skill '${name}' updated.` }] };
});
server.tool("delete_skill", "Delete a skill", { name: z.string().describe("Skill name") }, async ({ name }) => {
    run(`ai-inst skill rm ${name}`);
    return { content: [{ type: "text", text: `Skill '${name}' deleted.` }] };
});
server.tool("add_project_skill", "Add skills to a project", {
    project_path: z.string().describe("Absolute path to the project directory"),
    skills: z.array(z.string()).describe("Skill names to add"),
}, async ({ project_path, skills }) => {
    const output = run(`ai-inst project add-skill ${skills.join(" ")}`, project_path);
    return { content: [{ type: "text", text: output }] };
});
server.tool("remove_project_skill", "Remove skills from a project", {
    project_path: z.string().describe("Absolute path to the project directory"),
    skills: z.array(z.string()).describe("Skill names to remove"),
}, async ({ project_path, skills }) => {
    const output = run(`ai-inst project rm-skill ${skills.join(" ")}`, project_path);
    return { content: [{ type: "text", text: output }] };
});
server.tool("migrate", "Apply pending migrations or create a new migration. Migrations are YAML rules in the rules repo (migrations/*.yml) that auto-update project config when modules are renamed, split, or extracted into skills. Called automatically during build; use this tool directly to preview, apply, or create migrations.", {
    project_path: z.string().describe("Absolute path to the project directory"),
    status: z.boolean().optional().describe("If true, list all migrations with their applied/pending state without applying any changes"),
    create: z.string().optional().describe("Create a new migration with this slug (e.g. 'extract-foo-skill')"),
    description: z.string().optional().describe("Migration description (used with create)"),
    rules: z.array(z.object({
        when: z.string().describe("Condition, e.g. 'has_module:foo'"),
        then: z.string().describe("Actions, comma-separated, e.g. 'remove_module:foo,add_skill:bar'"),
    })).optional().describe("Migration rules (used with create)"),
}, async ({ project_path, status, create, description, rules }) => {
    if (create) {
        const args = [`--create`, create];
        if (description)
            args.push(`--description`, description);
        if (rules) {
            for (const rule of rules) {
                args.push(`--rule`, `${rule.when}->${rule.then}`);
            }
        }
        const escaped = args.map(a => `"${a.replace(/"/g, '\\"')}"`).join(" ");
        const output = run(`ai-inst migrate ${escaped}`, project_path);
        return { content: [{ type: "text", text: output }] };
    }
    const flag = status ? " --status" : "";
    const output = run(`ai-inst migrate${flag}`, project_path);
    return { content: [{ type: "text", text: output || "No pending migrations." }] };
});
server.tool("sync", "Sync rules repository (pull + push)", {}, async () => {
    const output = run("ai-inst repo sync");
    return { content: [{ type: "text", text: output }] };
});
// ─── Start ───────────────────────────────────────────────────────────────────
async function main() {
    const transport = new StdioServerTransport();
    await server.connect(transport);
}
main().catch((err) => {
    console.error("MCP server error:", err);
    process.exit(1);
});

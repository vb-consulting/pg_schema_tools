const templateFile = "template.sql";
const srcDir = "src/";
const buildFile = "build.sql";
const schema = "schema";
const host = "localhost";
const port = "5433";
const dbname = "dvdrental";
const username = "postgres";
const runCommand = `psql --host=${host} --port=${port} --dbname=${dbname} --username=${username} --file=${buildFile}`;

const fs = require("fs");
const path = require("path");
const cp = require("child_process");

const template = 'return `' + fs.readFileSync(templateFile, "utf8") + '`';
const data = {schema};
const render = () => new Function(template).call(data);
const exec = cmd => new Promise(resolve => {
    console.info(cmd);
    let exec = cp.exec(cmd);
    exec.stdout.on("data", data => { if (data) { console.info(data); } });
    exec.stderr.on("data", data => { if (data) { console.error(data); } });
    exec.on("exit", () => resolve());
});

const files = fs.readdirSync(srcDir)
for(let file of files) {
    const key = path.parse(file).name;
    data[key] = '/* #region ' + key + ' */\n' + 
        fs.readFileSync(path.join(srcDir, file), "utf8").trim() +
        '\n/* #endregion ' + key + ' */';
}

fs.writeFileSync(buildFile, render(), "utf8"); 

console.info("Build complete.");
console.info("File " + buildFile + " created.");
console.info("Executing...");

exec(runCommand).then(() => console.info("Done."));
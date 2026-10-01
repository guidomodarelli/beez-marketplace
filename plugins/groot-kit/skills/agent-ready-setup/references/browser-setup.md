# Browser setup

Bootstrap ejecuta `scripts/setup-browser-tools.py` después de proyectar assets.
Requiere Python 3.11+, Node.js 24+ y npm; no actualiza runtimes ni usa sudo.
Reutiliza `tomlkit` disponible para preservar TOML, o lo instala mediante pip en
directorio privado `browser-tools/python` según `scripts/requirements-browser.txt`;
pip solo hace falta si esa dependencia no está disponible. No instala paquetes
Python en entorno global.
Las versiones de Chrome DevTools MCP, Playwright MCP y agent-browser viven únicamente
en `scripts/browser-tools.json`. npm instala esos paquetes bajo
`~/.local/share/agent-ready-setup/browser-tools/<versions>/`, sin agregar dependencias
al proyecto ni modificar instalaciones globales existentes. Reutiliza paquetes de
la versión fijada y descarga Chromium mediante Playwright cuando falta; los tres
tools usan ese executable, evitando tres descargas de browser.

Agrega servidores ausentes en `.mcp.json` raíz (Claude) y `.codex/config.toml`
(Codex). Conserva servidores existentes, incluidos aliases conocidos y definiciones
globales y scope local de Claude en `~/.claude.json` o
`$CLAUDE_CONFIG_DIR/.claude.json`; no reemplaza commands,
credenciales, flags o decisiones de disabled. Conserva mapas TOML inline y
comentarios con editor real, sin convertirlos mediante regex.
JSON/TOML inválido, symlinks y cambios concurrentes se reportan sin sobrescribir.
Registros nuevos de Chrome DevTools y Playwright usan `--isolated` para evitar
conflictos con perfiles abiertos. En Linux sin `DISPLAY` ni `WAYLAND_DISPLAY`,
registros nuevos usan `--headless`. Registro parcial conserva progreso: intenta
ambos providers y termina con error si alguno queda pendiente.
Reejecutar bootstrap completa pasos faltantes sin
reinstalar paquetes cuya versión ya coincide.
Reutilización exige también ejecutables presentes; una extracción parcial de npm
vuelve a instalación. El MCP de agent-browser hereda Chromium mediante
`env.AGENT_BROWSER_EXECUTABLE_PATH`; flag CLI no configura sus invocaciones MCP.

`.agents/browser-tools.json` registra paths de CLI y browser para skill común
`agent-browser`; agents y comandos también pueden usar el MCP registrado.
Generar configuración no concede confianza: reiniciar provider y completar su
confirmación de MCP/proyecto cuando corresponda. Codex carga configuración local
solo en proyectos confiables. Bootstrap no modifica confianza, SSO/MFA, remote
debugging ni sesión personal. `cua` se detecta en herramientas expuestas por host;
no tiene instalador portable en este bootstrap.

Instalación fallida deja assets proyectados, termina con exit no cero y permite
reintentar. Diagnóstico de operación fallida queda en log temporal privado cuyo
path se reporta; no imprimir contenido raw. Operaciones externas tienen timeout
de 600 segundos y cancelan procesos hijos al vencer; instalación
simultánea queda bloqueada por lock y requiere reejecución posterior. Linux puede
necesitar bibliotecas de sistema para lanzar Chromium; bootstrap no las instala
con privilegios elevados. SessionStart sincroniza assets, no descarga paquetes.
Para CI o entorno offline: `AGENT_READY_SETUP_BROWSER_INSTALL=0` omite instalación
y registro; valor predeterminado `1`. No reportar browser listo si se omitió o falló.

Fuentes: [Chrome DevTools MCP](https://github.com/ChromeDevTools/chrome-devtools-mcp),
[Playwright MCP](https://github.com/microsoft/playwright-mcp),
[agent-browser](https://github.com/vercel-labs/agent-browser),
[Codex MCP](https://learn.chatgpt.com/docs/extend/mcp?surface=cli).

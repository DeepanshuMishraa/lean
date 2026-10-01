/* Lean's deterministic page interpreter. No site selectors or page-world hooks. */
(function () {
    'use strict';
    if (globalThis.LeanPageTheme) return;
    if (!['http:', 'https:'].includes(location.protocol)
        && !(window !== window.top && location.protocol === 'about:')) return;

    const attribute = 'data-lean-theme-';
    const roles = ['canvas', 'surface', 'raised', 'text', 'textMuted', 'border', 'accent',
        'danger', 'success', 'warning', 'info'];
    const records = new Map();
    const scopes = new Map();
    const dirty = new Set();
    const rules = new Map();
    const palette = new Map();
    const textPalette = new Map();
    const variableUses = new Map();
    const parsedColors = new Map();
    const constructedSheets = new WeakSet();
    const importantElements = new Set();
    let colorContext = null;
    let theme = null;
    let frame = 0;
    let generation = 0;
    let scanning = [];
    let scanTimer = 0;
    let hoverTimer = 0;
    let veil = null;
    let veilTimer = 0;
    const hovered = new Set();
    let dominantCanvas = null;
    let primaryText = null;
    const visibility = new IntersectionObserver(entries => {
        if (!theme) return;
        // Observation fires once per element on registration; only promote nodes not yet classified.
        for (const entry of entries) if (entry.isIntersecting && !records.get(entry.target)?.source) enqueueTree(entry.target);
        schedule();
    }, {rootMargin: '400px'});

    function parse(value) {
        if (typeof value !== 'string') return null;
        const hex = /^#([\da-f]{6})$/i.exec(value);
        if (hex) {
            const n = parseInt(hex[1], 16);
            return [n >> 16, n >> 8 & 255, n & 255, 1];
        }
        const rgb = /^rgba?\(\s*([\d.]+)[,\s]+([\d.]+)[,\s]+([\d.]+)(?:\s*[,/]\s*([\d.]+))?\s*\)$/i.exec(value);
        if (!rgb) {
            if (parsedColors.has(value)) return parsedColors.get(value);
            if (!CSS.supports('color', value) || /var\(|currentcolor|inherit|initial|unset/i.test(value)) return null;
            if (!colorContext) colorContext = document.createElement('canvas').getContext('2d', {willReadFrequently: true});
            if (!colorContext) return null;
            colorContext.clearRect(0, 0, 1, 1);
            colorContext.fillStyle = value;
            colorContext.fillRect(0, 0, 1, 1);
            const bytes = colorContext.getImageData(0, 0, 1, 1).data;
            const color = [bytes[0], bytes[1], bytes[2], bytes[3] / 255];
            if (parsedColors.size >= 1024) parsedColors.clear();
            parsedColors.set(value, color);
            return color;
        }
        const color = [Number(rgb[1]), Number(rgb[2]), Number(rgb[3]), rgb[4] === undefined ? 1 : Number(rgb[4])];
        return color.every(Number.isFinite) && color.slice(0, 3).every(v => v >= 0 && v <= 255)
            && color[3] >= 0 && color[3] <= 1 ? color : null;
    }
    function css(c) { return `rgba(${c.slice(0, 3).map(v => Math.round(v)).join(', ')}, ${c[3]})`; }
    function blend(fg, bg) {
        return fg.slice(0, 3).map((v, i) => v * fg[3] + bg[i] * (1 - fg[3])).concat(1);
    }
    function luminance(c) {
        const channels = c.slice(0, 3).map(v => {
            v /= 255;
            return v <= 0.04045 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4);
        });
        return channels[0] * 0.2126 + channels[1] * 0.7152 + channels[2] * 0.0722;
    }
    function contrast(a, b) {
        const x = luminance(blend(a, b)), y = luminance(b);
        return (Math.max(x, y) + 0.05) / (Math.min(x, y) + 0.05);
    }
    function readable(fg, bg, minimum) {
        if (contrast(fg, bg) >= minimum) return fg;
        const black = [0, 0, 0, 1], white = [255, 255, 255, 1];
        const pole = contrast(black, bg) > contrast(white, bg) ? black : white;
        // Keep the token's hue as far as the contrast requirement permits.
        let lo = 0, hi = 1;
        for (let i = 0; i < 12; i++) {
            const t = (lo + hi) / 2;
            const candidate = fg.slice(0, 3).map((v, j) => v + (pole[j] - v) * t).concat(1);
            if (contrast(candidate, bg) >= minimum) hi = t; else lo = t;
        }
        // Round toward the selected pole so quantization cannot lower contrast.
        return fg.slice(0, 3).map((v, j) => {
            const result = v + (pole[j] - v) * hi;
            return pole[j] === 0 ? Math.floor(result) : Math.ceil(result);
        }).concat(1);
    }
    function neutral(c) {
        if (!c) return false;
        const max = Math.max(...c.slice(0, 3)), min = Math.min(...c.slice(0, 3));
        return max - min <= 40 || (max - min <= 65 && max < 90);
    }
    function hue(c) {
        const [r, g, b] = c;
        const max = Math.max(r, g, b), min = Math.min(r, g, b), d = max - min;
        if (!d) return 0;
        let h = max === r ? (g - b) / d : max === g ? 2 + (b - r) / d : 4 + (r - g) / d;
        return (h * 60 + 360) % 360;
    }
    function semantic(c, el, interactive) {
        if (!c || neutral(c)) return null;
        const h = hue(c), role = el.getAttribute('role');
        if (el.matches('a[href], [role="link"]')) return 'accent';
        if (interactive && role !== 'status' && role !== 'alert') {
            const label = `${el.getAttribute('aria-label') || ''} ${el.textContent.slice(0, 80)}`;
            if ((h < 25 || h > 335) && /\b(delete|remove|erase|discard|destroy|reject)\b/i.test(label)) return 'danger';
            return 'accent';
        }
        // Hue alone cannot distinguish a brand color from an error or a chart legend.
        if (role !== 'status' && role !== 'alert') return null;
        if (h < 25 || h > 335) return 'danger';
        if (h >= 65 && h < 170) return 'success';
        if (h >= 25 && h < 65) return 'warning';
        return 'info';
    }
    function parentOf(el) {
        return el.parentElement || (el.getRootNode().host || null);
    }
    function media(el) {
        if (el.closest('img, picture, video, canvas, iframe, object, embed, [role="img"]')) return true;
        const svg = el.closest('svg');
        if (!svg) return false;
        const rect = svg.getBoundingClientRect();
        // ponytail: monochrome small SVGs only; complex artwork needs an image classifier.
        const label = `${svg.getAttribute('aria-label') || ''} ${svg.querySelector('title')?.textContent || ''}`;
        if (rect.width > 48 || rect.height > 48 || /logo|brand|illustration|chart|graph/i.test(label)
            || svg.querySelector('image, text, foreignObject, linearGradient, radialGradient')) return true;
        const paints = new Set();
        for (const node of svg.querySelectorAll('path, rect, circle, ellipse, line, polygon, polyline, use')) {
            for (const p of ['fill', 'stroke']) {
                const c = parse(getComputedStyle(node)[p]);
                if (c && c[3]) paints.add(css(c));
            }
            if (paints.size > 1) return true;
        }
        return false;
    }
    function fingerprint(el, pseudo = null, rect = el.getBoundingClientRect()) {
        const style = getComputedStyle(el, pseudo);
        const role = el.getAttribute('role');
        // An inherited paint reads as the parent's themed value; recover the site's original instead.
        const parent = pseudo ? null : parentOf(el);
        const parentStyle = parent ? getComputedStyle(parent) : null;
        const paint = property => (parentStyle && style[property] === parentStyle[property]
            ? records.get(parent)?.source?.[property] : null) || parse(style[property]);
        const interactive =el.matches('button, a[href], input, select, textarea, summary, [role="button"], [role="link"], [role="tab"]')
            || el.hasAttribute('onclick') || (el.hasAttribute('tabindex') && el.tabIndex >= 0) || style.cursor === 'pointer';
        return {
            background: parse(style.backgroundColor), color: paint('color'),
            borders: ['Top', 'Right', 'Bottom', 'Left'].map(side =>
                parseFloat(style[`border${side}Width`]) > 0 ? parse(style[`border${side}Color`]) : null),
            fill: paint('fill'), stroke: paint('stroke'),
            focus: !pseudo && el.matches(':focus-visible'),
            outline: parseFloat(style.outlineWidth) > 0 && style.outlineStyle !== 'none' ? parse(style.outlineColor) : null,
            width: rect.width, height: rect.height, area: rect.width * rect.height,
            viewportArea: Math.max(0, Math.min(rect.right, innerWidth) - Math.max(0, rect.left))
                * Math.max(0, Math.min(rect.bottom, innerHeight) - Math.max(0, rect.top)),
            visible: style.display !== 'none' && style.visibility !== 'hidden' && rect.width > 0 && rect.height > 0,
            image: style.backgroundImage !== 'none', imageValue: style.backgroundImage, opacity: Number(style.opacity),
            fixed: style.position === 'fixed' || style.position === 'sticky',
            elevated: role === 'dialog' || el.matches('dialog, [popover]') || style.boxShadow !== 'none',
            card: parseFloat(style.borderRadius) > 0 || parseFloat(style.paddingTop) > 0 || parseFloat(style.paddingLeft) > 0,
            heading: el.matches('h1, h2, h3, h4, h5, h6, [role="heading"]'),
            large: parseFloat(style.fontSize) >= 24 || (parseFloat(style.fontSize) >= 18.66 && Number(style.fontWeight) >= 700),
            interactive, control: el.matches('input, select, textarea'),
            text: pseudo ? style.content !== 'none' && style.content !== 'normal'
                : [...el.childNodes].some(n => n.nodeType === Node.TEXT_NODE && n.textContent.trim()),
            pseudo: pseudo ? style.content !== 'none' && style.content !== 'normal' : false,
            icon: Boolean(el.closest('svg'))
        };
    }
    function originalBackground(el) {
        for (let current = el; current; current = parentOf(current)) {
            const record = records.get(current);
            if (record?.source?.background && record.source.background[3] > 0.9) return record.source.background;
        }
        return [255, 255, 255, 1];
    }
    function backdrop(el) {
        const stack = [];
        for (let current = el; current; current = parentOf(current)) {
            const record = records.get(current);
            if (record) stack.push(record);
        }
        let result = parse(theme.background);
        for (const record of stack.reverse()) {
            if (record.background) result = blend(token(record.background), result);
            else if (record.source?.background) result = blend(record.source.background, result);
        }
        return result;
    }
    function token(spec) {
        const base = parse(theme[spec.role === 'canvas' ? 'background' : spec.role]);
        return base.slice(0, 3).concat(spec.alpha === undefined ? base[3] : spec.alpha);
    }
    function unregisterColors(record) {
        if (!record.source) return;
        function subtract(histogram, color, weight) {
            if (!color) return;
            const key = css(color), remaining = (histogram.get(key) || 0) - weight;
            if (remaining > 0) histogram.set(key, remaining); else histogram.delete(key);
        }
        subtract(palette, record.source.background, record.weight);
        if (record.source.text) subtract(textPalette, record.source.color, 1);
    }
    function resetImportant(record) {
        for (const [property, saved] of record.inline) {
            const style = record.element.style;
            // Do not overwrite a newer site-authored value when disabling or rescanning.
            if (style.getPropertyValue(property) === saved.written && style.getPropertyPriority(property) === 'important') {
                style.setProperty(property, saved.original, saved.priority);
            }
        }
        record.inline.clear();
        importantElements.delete(record);
        record.ownStyle = record.element.getAttribute('style');
    }
    function installImportant(record, spec) {
        if (spec.pseudo || record.element.style.getPropertyPriority(spec.property) !== 'important') return;
        const style = record.element.style;
        const original = style.getPropertyValue(spec.property);
        style.setProperty(spec.property, ruleValue(spec), 'important');
        record.inline.set(spec.property, {original, priority: 'important', written: style.getPropertyValue(spec.property)});
        record.ownStyle = record.element.getAttribute('style');
        importantElements.add(record);
    }
    function restore(record) {
        resetImportant(record);
        for (const [name, original] of record.attributes) {
            if (original === null) record.element.removeAttribute(name); else record.element.setAttribute(name, original);
        }
        record.attributes.clear();
        record.specs.clear();
        record.background = null;
    }
    function assign(record, property, spec, pseudo = '') {
        const name = `${attribute}${pseudo}${property}`;
        const key = `${spec.role}-${spec.alpha ?? 1}-${spec.on || ''}-${spec.minimum || ''}-${spec.literal ? css(spec.literal).replace(/[^\w.-]/g, '-') : ''}${spec.gradient ? hash(spec.gradient) : ''}`;
        record.specs.set(name, {...spec, property, pseudo, key});
        rules.set(`${name}:${key}`, {...spec, property, pseudo, key});
        installImportant(record, {...spec, property, pseudo});
        if (!record.attributes.has(name)) record.attributes.set(name, record.element.getAttribute(name));
        if (record.element.getAttribute(name) !== key) record.element.setAttribute(name, key);
        if (property === 'background-color' && !pseudo) record.background = spec;
    }
    function classify(record, source, pseudo = '') {
        const el = record.element;
        if (record.media) {
            if (!pseudo && source.color) assign(record, 'color', {role: 'preserve', literal: source.color});
            return;
        }
        if (!source.visible || (pseudo && !source.pseudo)) return;
        const parent = parentOf(el);
        const parentBg = originalBackground(parent);
        const bg = source.background;
        const isRoot = !pseudo && (el === document.documentElement || el === document.body);
        let backgroundRole = null, confidence = 0;
        if (isRoot) { backgroundRole = 'canvas'; confidence = 1; }
        else if (bg && bg[3] > 0 && !source.image) {
            if (neutral(bg)) {
                const distance = Math.max(...bg.slice(0, 3).map((v, i) => Math.abs(v - parentBg[i])));
                const coverage = source.area / Math.max(1, innerWidth * innerHeight);
                // Pinned bars (headers, sidebars) share the page's own background; only a distinct one is raised.
                const matchesPage = distance <= 6
                    || (dominantCanvas && Math.max(...bg.slice(0, 3).map((v, i) => Math.abs(v - dominantCanvas[i]))) <= 6);
                // A primary button drawn light-on-dark (or dark-on-light) is inverted, not a card: keep it loud.
                if (source.interactive && !source.control && contrast(bg, parentBg) >= 4) { backgroundRole = 'text'; confidence = 0.95; }
                else if (source.elevated || (source.fixed && !matchesPage)) { backgroundRole = 'raised'; confidence = 0.95; }
                else if (source.control || (source.card && (distance > 6 || source.borders.some(color => color && color[3] > 0)))) {
                    backgroundRole = 'surface'; confidence = 0.92;
                }
                else if (coverage > 0.45 || distance <= 6
                    || (dominantCanvas && Math.max(...bg.slice(0, 3).map((v, i) => Math.abs(v - dominantCanvas[i]))) <= 6)) {
                    backgroundRole = 'canvas'; confidence = 0.9;
                    for (let ancestor = parent; ancestor; ancestor = parentOf(ancestor)) {
                        const inherited = records.get(ancestor)?.background;
                        if (inherited) { backgroundRole = inherited.role; break; }
                    }
                    // Dialogs often reuse the page's own color for their panels; they still sit above the page.
                    if (backgroundRole === 'canvas' && el.closest('[role="dialog"], [aria-modal="true"], dialog, [popover]')) backgroundRole = 'raised';
                } else if (distance > 6) { backgroundRole = 'surface'; confidence = 0.75; }
            } else if (source.interactive) {
                backgroundRole = semantic(bg, el, true); confidence = 0.9;
            }
        }
        // A graph node has a role, source fingerprint and parent, not a site-specific selector.
        // Confidence is a heuristic evidence score, not a calibrated ML probability.
        if (!pseudo) {
            record.role = backgroundRole || (source.interactive ? 'control' : source.heading ? 'heading' : source.icon ? 'icon' : source.text ? 'text' : 'unknown');
            record.confidence = backgroundRole ? confidence : record.role === 'unknown' ? 0 : 0.9;
            record.parent = parent;
        }
        if (backgroundRole && confidence >= 0.85) {
            if (backgroundRole === 'surface') {
                for (let ancestor = parent; ancestor; ancestor = parentOf(ancestor)) {
                    if (records.get(ancestor)?.background?.role === 'surface') { backgroundRole = 'raised'; break; }
                    if (records.get(ancestor)?.background) break;
                }
            }
            assign(record, 'background-color', {role: backgroundRole, alpha: isRoot ? 1 : bg?.[3] ?? 1}, pseudo);
        }
        const effective = backdrop(el);
        const on = css(effective).replace(/[^\w.-]/g, '-');
        const minimum = source.large ? 3 : 4.5;
        const color = source.color;
        // Fully transparent text is hidden on purpose (fades, screen-reader copies); never make it visible.
        if (color && color[3] > 0 && (source.text || source.interactive || source.heading || source.icon || isRoot)) {
            let foreground = null;
            // Only links the site itself colored are accent; neutral link text (titles, nav) is body text.
            let inverted = backgroundRole === 'text';
            if (!inverted) {
                for (let ancestor = parent; ancestor; ancestor = parentOf(ancestor)) {
                    const inherited = records.get(ancestor)?.background;
                    if (inherited) { inverted = inherited.role === 'text'; break; }
                }
            }
            if (inverted && neutral(color)) foreground = 'canvas';
            else if (source.heading || isRoot || el.closest('h1, h2, h3, h4, h5, h6, [role="heading"]')) foreground = 'text';
            else if (!neutral(color) && el.closest('a[href], [role="link"]')) foreground = 'accent';
            else if (neutral(color)) {
                const ratio = contrast(color, originalBackground(el));
                foreground = css(color) === primaryText || ratio >= 7 || source.control ? 'text' : 'textMuted';
            } else if (!el.closest('pre, code, kbd, samp')) foreground = semantic(color, el, source.interactive);
            if (foreground) {
                // Low-confidence surfaces keep their original appearance; only correct unsafe text.
                assign(record, 'color', {role: foreground, on, backdrop: effective, minimum}, pseudo);
            } else if (!el.closest('pre, code, kbd, samp')) {
                // Unknown colored text keeps its hue; correct legibility without inventing intent.
                assign(record, 'color', {role: 'preserve', literal: color, on, backdrop: effective, minimum}, pseudo);
            }
        }
        source.borders.forEach((color, i) => {
            // Card outlines stay uniform even when a site tints one (a red warning card); controls keep their hue.
            if (color && color[3] > 0 && (neutral(color) || (!source.interactive && !source.control && !source.focus))) {
                const spec = {role: 'border', alpha: color[3]};
                if (source.control || source.interactive) Object.assign(spec, {on, backdrop: effective, minimum: 3});
                assign(record, `border-${['top', 'right', 'bottom', 'left'][i]}-color`, spec, pseudo);
            }
        });
        if (source.focus && source.outline) {
            const outside = backdrop(parent);
            assign(record, 'outline-color', {role: 'accent', on: css(outside).replace(/[^\w.-]/g, '-'), backdrop: outside, minimum: 3});
        }
        if (source.image && /^linear-gradient\(/.test(source.imageValue) && !/url\(/.test(source.imageValue)
            && source.imageValue.split('gradient(').length === 2) {
            const stops = source.imageValue.match(/rgba?\([^)]*\)/g) || [];
            if (stops.length && stops.every(stop => neutral(parse(stop)))) {
                const under = backdrop(parent);
                assign(record, 'background-image', {role: 'gradient', gradient: source.imageValue, on: css(under).replace(/[^\w.-]/g, '-'), backdrop: under}, pseudo);
            }
        }
        if (source.icon) {
            for (const property of ['fill', 'stroke']) {
                const c = source[property];
                if (c && c[3] > 0 && neutral(c)) assign(record, property, {role: 'text', alpha: c[3], on, backdrop: effective, minimum: 3}, pseudo);
            }
        }
    }
    function hash(text) {
        let h = 5381;
        for (let i = 0; i < text.length; i++) h = (h * 33 ^ text.charCodeAt(i)) >>> 0;
        return h.toString(36);
    }
    // Fade overlays (page-to-composer gradients) are drawn in the site's colors; re-tint their stops.
    function themedGradient(spec) {
        const [r, g, b] = spec.backdrop;
        return spec.gradient.replace(/rgba?\([^)]*\)/g, stop => `rgba(${Math.round(r)}, ${Math.round(g)}, ${Math.round(b)}, ${parse(stop)?.[3] ?? 1})`);
    }
    function ruleValue(spec) {
        if (spec.gradient) return themedGradient(spec);
        let color = spec.literal || token({...spec, role: spec.role === 'canvas' ? 'background' : spec.role});
        if (spec.backdrop) color = readable(color, spec.backdrop, spec.minimum);
        return css(color);
    }
    function ruleText(spec) {
        return `[${attribute}${spec.pseudo}${spec.property}="${spec.key}"]${spec.pseudo ? '::' + spec.pseudo.slice(0, -1) : ''}{${spec.property}:${ruleValue(spec)} !important;}\n`;
    }
    // Inserting a rule restyles only what it matches; replacing the sheet restyles the whole page.
    function appendRules() {
        for (const scope of scopes.values()) {
            const sheet = scope.constructed || scope.style.sheet;
            if (!sheet || !scope.emitted) { updateStyles(); return; }
            for (const [id, spec] of rules) {
                if (scope.emitted.has(id)) continue;
                try { sheet.insertRule(ruleText(spec), sheet.cssRules.length); } catch (error) { updateStyles(); return; }
                scope.emitted.add(id);
            }
        }
    }
    function updateStyles() {
        if (!theme) return;
        for (const [root, scope] of scopes) {
            if (root !== document && !root.host.isConnected) { scope.observer.disconnect(); scopes.delete(root); continue; }
            let text = root === document
                ? `:root{color-scheme:${theme.isDark ?? (luminance(parse(theme.background)) < 0.45) ? 'dark' : 'light'};}html,body{background-color:${css(parse(theme.background))} !important;color:${css(parse(theme.text))} !important;}\n`
                : '';
            for (const spec of rules.values()) text += ruleText(spec);
            text += variableOverrides(root);
            scope.emitted = new Set(rules.keys());
            if (scope.text !== text) {
                if (!scope.constructed) {
                    scope.style.textContent = text;
                    if (!scope.style.sheet && Array.isArray(root.adoptedStyleSheets)) {
                        scope.constructed = new CSSStyleSheet();
                        constructedSheets.add(scope.constructed);
                        root.adoptedStyleSheets = [...root.adoptedStyleSheets, scope.constructed];
                    }
                }
                if (scope.constructed) scope.constructed.replaceSync(text);
                scope.text = text;
            }
        }
    }
    function discoverVariables(root) {
        const uses = new Map();
        function visit(cssRules) {
            for (const rule of cssRules) {
                if (rule.style) {
                    for (const property of new Set([...rule.style, 'background', 'border', 'border-color'])) {
                        if (property.startsWith('--')) continue;
                        const kind = property === 'color' ? 'text' : property.includes('background') ? 'background'
                            : property.startsWith('border') ? 'border' : 'other';
                        for (const match of rule.style.getPropertyValue(property).matchAll(/var\(\s*(--[\w-]+)/g)) {
                            if (!uses.has(match[1])) uses.set(match[1], new Set());
                            uses.get(match[1]).add(kind);
                        }
                    }
                }
                if (rule.cssRules) visit(rule.cssRules);
            }
        }
        const sheets = root === document ? document.styleSheets : [...root.querySelectorAll('style, link')].map(el => el.sheet);
        for (const sheet of [...sheets, ...(root.adoptedStyleSheets || [])]) {
            if (!sheet || constructedSheets.has(sheet) || sheet.ownerNode?.hasAttribute('data-lean-theme-sheet')) continue;
            // Cross-origin sheets stay behind WebKit's security boundary.
            try { visit(sheet.cssRules); } catch (error) { if (error.name !== 'SecurityError') console.warn('Lean theme: CSSOM inspection failed', error); }
        }
        variableUses.set(root, uses);
    }
    function variableOverrides(root) {
        const scope = root === document ? document.documentElement : root.host;
        const source = records.get(scope)?.variables;
        if (!source) return '';
        let declarations = '';
        for (const [name, kinds] of variableUses.get(root) || []) {
            if (kinds.size !== 1 || kinds.has('other') || !/^--[\w-]+$/.test(name)) continue;
            const color = source.get(name);
            if (!color) continue;
            const lower = name.toLowerCase();
            let role = null;
            if (/border|divider|separator/.test(lower) && kinds.has('border') && neutral(color)) role = 'border';
            else if (/foreground|text|content/.test(lower) && kinds.has('text') && neutral(color)) role = /muted|secondary|subtle/.test(lower) ? 'textMuted' : 'text';
            else if (/background|canvas|surface/.test(lower) && kinds.has('background') && neutral(color)) role = /elevated|popover|modal/.test(lower) ? 'raised' : /surface|secondary/.test(lower) ? 'surface' : 'background';
            // Brand and mixed-use variables are not overwritten: their color alone is insufficient evidence.
            if (role) declarations += `${name}:${css(parse(theme[role]))} !important;`;
        }
        return declarations ? `${root === document ? ':root' : ':host'}{${declarations}}\n` : '';
    }
    function sheetSignature(root) {
        const sheets = root === document ? document.styleSheets : [...root.querySelectorAll('style, link')].map(el => el.sheet);
        return [...sheets, ...(root.adoptedStyleSheets || [])].map(sheet => {
            if (!sheet || constructedSheets.has(sheet) || sheet.ownerNode?.hasAttribute('data-lean-theme-sheet')) return '';
            // Full rule text is too costly on large sites. The count plus three sampled rules catches
            // replaced, inserted and removed rules; an in-place edit of an unsampled rule goes unseen.
            try {
                const list = sheet.cssRules, n = list.length;
                return `${sheet.href || ''}:${n}:${n ? list[0].cssText + list[n >> 1].cssText + list[n - 1].cssText : ''}`;
            }
            catch (error) { if (error.name === 'SecurityError') return sheet.href || ''; throw error; }
        }).join('\n');
    }
    // Drops records for a removed subtree, including open shadow roots and their observers.
    // Walks only that subtree; scanning every record per removal is quadratic.
    function forget(top) {
        const walker = document.createTreeWalker(top, NodeFilter.SHOW_ELEMENT);
        for (let el = top; el; el = walker.nextNode()) {
            const record = records.get(el);
            if (record) { unregisterColors(record); restore(record); visibility.unobserve(el); records.delete(el); }
            const shadow = el.shadowRoot;
            if (shadow) {
                const scope = scopes.get(shadow);
                if (scope) { scope.observer.disconnect(); scopes.delete(shadow); }
                for (const child of shadow.children) forget(child);
            }
        }
    }
    function addScope(root) {
        if (scopes.has(root)) return;
        const style = document.createElement('style');
        style.setAttribute('data-lean-theme-sheet', '');
        (root === document ? document.head || document.documentElement : root).appendChild(style);
        let constructed = null;
        // A site's CSP can reject inline style elements. Constructed sheets use the CSSOM,
        // preserving the policy for the site's own scripts and network requests.
        if (!style.sheet && Array.isArray(root.adoptedStyleSheets)) {
            constructed = new CSSStyleSheet();
            constructedSheets.add(constructed);
            root.adoptedStyleSheets = [...root.adoptedStyleSheets, constructed];
        }
        const observer = new MutationObserver(changes => {
            for (const change of changes) {
                if (change.target === style || style.contains(change.target)) continue;
                if (change.type === 'attributes' && change.attributeName.startsWith(attribute)) continue;
                if (change.type === 'attributes' && change.attributeName === 'style'
                    && records.get(change.target)?.ownStyle === change.target.getAttribute('style')) continue;
                if (change.type === 'childList') {
                    change.addedNodes.forEach(node => { if (node.nodeType === Node.ELEMENT_NODE && node !== style) enqueueTree(node); });
                    change.removedNodes.forEach(node => {
                        if (node.nodeType !== Node.ELEMENT_NODE || node.isConnected) return;
                        forget(node);
                    });
                }
                if (change.target.nodeType === Node.ELEMENT_NODE
                    && (change.target.matches('style, link') || change.target.closest('style'))) {
                    discoverVariables(root);
                    refresh();
                }
                if (change.type === 'childList' && [...change.addedNodes].some(node => node.nodeType === Node.ELEMENT_NODE && node.matches('style, link'))) {
                    discoverVariables(root);
                    refresh();
                }
                // Labels and data-* attributes do not restyle anything; skip the reread (and the sheet pause it forces).
                if (change.type === 'attributes' && /^(aria-label|aria-describedby|title|alt|href|src|id|data-(?!theme|state|active|selected))/.test(change.attributeName)) continue;
                if (change.type === 'attributes') {
                    // An attribute flip rarely restyles a whole subtree; recheck the element and its direct children.
                    dirty.add(change.target);
                    for (let i = 0; i < Math.min(change.target.children.length, 40); i++) dirty.add(change.target.children[i]);
                } else if (change.target.nodeType === Node.ELEMENT_NODE) dirty.add(change.target);
                else if (change.target.parentElement) dirty.add(change.target.parentElement);
            }
            if (!style.isConnected) (root === document ? document.head || document.documentElement : root).appendChild(style);
            flushNow();
        });
        observer.observe(root, {subtree: true, childList: true, attributes: true, characterData: true});
        scopes.set(root, {style, constructed, observer, signature: sheetSignature(root), text: ''});
        discoverVariables(root);
        updateStyles();
    }
    function enqueueTree(el) {
        dirty.add(el);
        if (scanning.some(scan => !scan.discovery && (scan.root === el || scan.root.contains(el)))) return;
        scanning.push({root: el, walker: document.createTreeWalker(el, NodeFilter.SHOW_ELEMENT), discovery: false});
    }
    function schedule() {
        if (!theme || frame) return;
        frame = setTimeout(flush, 40);
    }
    function flush(budget = 12) {
        frame = 0;
        // Pausing our sheets restyles the whole page, so never do it with nothing to read.
        if (!theme || (!dirty.size && !scanning.length)) return;
        // Each element is restored before it is read, so we never classify our own output.
        // Inherited paint is resolved from the parent's source. Only the root, body and hosts whose
        // custom properties we override need the whole sheet paused, since that restyles the page.
        let paused = false;
        const pause = () => {
            if (paused) return;
            paused = true;
            if (veil) veil.disabled = true;
            for (const scope of scopes.values()) {
                const sheet = scope.constructed || scope.style.sheet;
                if (sheet) sheet.disabled = true;
            }
        };
        const rulesBefore = rules.size;
        let fullUpdate = false;
        const batch = [];
        let start = performance.now();
        try {
            while (batch.length < 300 && performance.now() - start < budget) {
                let discovery = false;
                let el = dirty.values().next().value;
                if (el) dirty.delete(el);
                else if (scanning.length) {
                    discovery = scanning[0].discovery;
                    el = scanning[0].walker.nextNode();
                    if (!el) { scanning.shift(); continue; }
                } else break;
                if (!el.isConnected) continue;
                if (el.nodeType !== Node.ELEMENT_NODE) continue;
                if (discovery) {
                    // Discovery only looks for late shadow roots: no layout reads, no records.
                    if (el.shadowRoot && !scopes.has(el.shadowRoot)) {
                        addScope(el.shadowRoot);
                        enqueueTree(el.shadowRoot);
                    }
                    continue;
                }
                if (el.matches('script, style, link, meta, head, title, template')) continue;
                let record = records.get(el);
                if (!record) {
                    record = {element: el, attributes: new Map(), specs: new Map(), inline: new Map(), background: null, source: null, role: 'unknown', confidence: 0};
                    records.set(el, record);
                    visibility.observe(el);
                }
                const rect = el.getBoundingClientRect();
                // Classify the viewport first; native visibility events promote deferred graph nodes.
                if (rect.bottom < -400 || rect.top > innerHeight + 400) continue;
                // The media verdict is stable; recomputing it reads every SVG child's style.
                const protectedMedia = record.mediaKnown ? record.media : media(el);
                record.mediaKnown = true;
                if (protectedMedia && el.localName !== 'svg') {
                    record.media = true; record.role = 'media'; record.confidence = 1;
                    continue;
                }
                if (el.shadowRoot) {
                    const fresh = !scopes.has(el.shadowRoot);
                    if (fresh) addScope(el.shadowRoot);
                    if (fresh) enqueueTree(el.shadowRoot);
                }
                record.media = protectedMedia;
                if (protectedMedia) { record.role = 'media'; record.confidence = 1; }
                const hostScope = el.shadowRoot && scopes.get(el.shadowRoot);
                if (el === document.documentElement || el === document.body || (hostScope && hostScope.text.includes(':host'))) pause();
                restore(record);
                const source = fingerprint(el, null, rect);
                const pseudos = ['::before', '::after'].map(p => fingerprint(el, p, rect));
                unregisterColors(record);
                record.source = source;
                record.pseudos = pseudos;
                record.weight = source.viewportArea;
                if (el === document.documentElement || el.shadowRoot) {
                    record.variables = new Map();
                    fullUpdate = true;
                    const style = getComputedStyle(el);
                    for (const name of variableUses.get(el === document.documentElement ? document : el.shadowRoot)?.keys() || []) {
                        const value = parse(style.getPropertyValue(name).trim());
                        if (value) record.variables.set(name, value);
                    }
                }
                // Exclude the first style/layout synchronization from the per-node budget;
                // otherwise a large page can make every batch contain just one node.
                if (!batch.length) start = performance.now();
                batch.push([record, source, pseudos]);
                if (source.background && source.background[3] > 0 && neutral(source.background)) {
                    const key = css(source.background);
                    palette.set(key, (palette.get(key) || 0) + record.weight);
                }
                if (source.text && source.color && neutral(source.color)) {
                    const key = css(source.color);
                    textPalette.set(key, (textPalette.get(key) || 0) + 1);
                }
            }
        } finally {
            if (paused) {
                if (veil) veil.disabled = false;
                for (const scope of scopes.values()) {
                    const sheet = scope.constructed || scope.style.sheet;
                    if (sheet) sheet.disabled = false;
                }
            }
        }
        dominantCanvas = parse([...palette].sort((a, b) => b[1] - a[1])[0]?.[0]);
        primaryText = [...textPalette].sort((a, b) => b[1] - a[1])[0]?.[0] || null;
        for (const [record, source, pseudos] of batch) {
            classify(record, source);
            classify(record, pseudos[0], 'before-');
            classify(record, pseudos[1], 'after-');
        }
        // Rules only grow between theme changes; unused ones are harmless, so append instead of rebuilding.
        if (fullUpdate) updateStyles();
        else if (rules.size !== rulesBefore) appendRules();
        if (dirty.size || scanning.length) schedule();
        else if (document.readyState !== 'loading') lowerVeil();
    }
    // Run inside the observer callback: it fires before the next paint, so new content never shows unthemed.
    function flushNow() {
        if (!theme) return;
        clearTimeout(frame);
        frame = 0;
        flush(24);
    }
    function invalidate(event) {
        if (!theme) return;
        let target = event.target?.nodeType === Node.ELEMENT_NODE ? event.target : document.body;
        // Hover and focus restyle the element and a few ancestors; never rescan the subtree.
        // Only elements that can paint a hover or focus state are worth rereading.
        for (let i = 0; target && i < 3; i++, target = parentOf(target)) {
            const source = records.get(target)?.source;
            if (source && (source.interactive || source.control || (source.background && source.background[3] > 0))) hovered.add(target);
        }
        // Debounce: each reread pauses our sheet and restyles the page, so wait for the pointer to settle.
        clearTimeout(hoverTimer);
        hoverTimer = setTimeout(() => {
            for (const el of hovered) dirty.add(el);
            hovered.clear();
            schedule();
        }, 150);
    }
    function refresh() {
        if (!theme || scanning.length) return;
        for (const root of scopes.keys()) {
            discoverVariables(root);
            // A shadow root's styles changed too: its content needs rereading, not just the document's.
            enqueueTree(root === document ? document.documentElement : root);
        }
        schedule();
    }
    function poll() {
        if (!theme || scanning.length) return;
        let changed = false;
        for (const [root, scope] of scopes) {
            if (scope.constructed && !root.adoptedStyleSheets.includes(scope.constructed)) {
                root.adoptedStyleSheets = [...root.adoptedStyleSheets, scope.constructed];
            }
            const signature = sheetSignature(root);
            if (signature !== scope.signature) { scope.signature = signature; changed = true; }
        }
        if (changed) refresh();
        else {
            scanning.push({root: document, walker: document.createTreeWalker(document, NodeFilter.SHOW_ELEMENT), discovery: true});
            schedule();
        }
    }
    function sendToChildren() {
        for (let i = 0; i < window.frames.length; i++) {
            window.frames[i].postMessage({type: 'lean-page-theme', theme}, '*');
        }
    }
    function raiseVeil() {
        if (veil || document.readyState !== 'loading' || !Array.isArray(document.adoptedStyleSheets)) return;
        veil = new CSSStyleSheet();
        constructedSheets.add(veil);
        // Hide the body, not the root: a hidden root exposes the web view's own white or grey, which is
        // the flash. Opacity, not visibility, because visibility is inherited and would blind the scan.
        veil.replaceSync(`html{background-color:${css(parse(theme.background))} !important;}html>body{opacity:0 !important;}`);
        document.adoptedStyleSheets = [...document.adoptedStyleSheets, veil];
        veilTimer = setTimeout(lowerVeil, 1500);
    }
    function lowerVeil() {
        clearTimeout(veilTimer);
        if (!veil) return;
        document.adoptedStyleSheets = document.adoptedStyleSheets.filter(sheet => sheet !== veil);
        veil = null;
    }
    function stop() {
        lowerVeil();
        clearTimeout(frame); frame = 0;
        clearInterval(scanTimer); scanTimer = 0;
        clearTimeout(hoverTimer); hovered.clear();
        scanning = []; dirty.clear(); visibility.disconnect();
        for (const scope of scopes.values()) scope.observer.disconnect();
        for (const record of records.values()) restore(record);
        for (const [root, scope] of scopes) {
            if (scope.constructed) root.adoptedStyleSheets = root.adoptedStyleSheets.filter(sheet => sheet !== scope.constructed);
            scope.style.remove();
        }
        records.clear(); scopes.clear(); rules.clear(); palette.clear(); textPalette.clear(); variableUses.clear(); parsedColors.clear();
        dominantCanvas = null; primaryText = null; importantElements.clear();
        for (const type of ['pointerover', 'pointerout', 'focusin', 'focusout', 'input', 'change', 'transitionend']) document.removeEventListener(type, invalidate, true);
        window.removeEventListener('resize', refresh);
        window.removeEventListener('popstate', refresh);
    }
    function apply(next) {
        if (next !== null) {
            if (!next || typeof next !== 'object' || (next.isDark !== undefined && typeof next.isDark !== 'boolean')
                || roles.some(role => !parse(next[role === 'canvas' ? 'background' : role]))) return;
            // Only public theme tokens cross frame boundaries, never arbitrary message fields.
            const normalized = Object.fromEntries(roles.map(role => {
                const key = role === 'canvas' ? 'background' : role;
                return [key, css(parse(next[key]))];
            }));
            if (next.isDark !== undefined) normalized.isDark = next.isDark;
            next = Object.freeze(normalized);
        }
        if (theme && next) {
            theme = next;
            generation++;
            rules.clear();
            for (const record of records.values()) {
                restore(record);
                if (!record.source) continue;
                classify(record, record.source);
                classify(record, record.pseudos[0], 'before-');
                classify(record, record.pseudos[1], 'after-');
            }
            updateStyles();
            sendToChildren();
            return;
        }
        stop();
        theme = next;
        generation++;
        if (theme) {
            const begin = () => {
                if (!theme || !document.documentElement || scopes.has(document)) return;
                // Cover the page until the first full pass, so the site's own colors never paint.
                raiseVeil();
                addScope(document);
                enqueueTree(document.documentElement);
                schedule();
            };
            if (document.documentElement) begin();
            else {
                // The root element appears before first paint; do not wait for DOMContentLoaded.
                const rootWatch = new MutationObserver(() => { if (document.documentElement) { rootWatch.disconnect(); begin(); } });
                rootWatch.observe(document, {childList: true});
            }
            if (document.readyState === 'loading') {
                document.addEventListener('DOMContentLoaded', () => {
                    if (!theme) return;
                    begin();
                    enqueueTree(document.documentElement);
                    schedule();
                }, {once: true});
            }
            for (const type of ['pointerover', 'pointerout', 'focusin', 'focusout', 'input', 'change', 'transitionend']) document.addEventListener(type, invalidate, true);
            window.addEventListener('resize', refresh);
            window.addEventListener('popstate', refresh);
            // Page-world attachShadow/history/CSSOM hooks are deliberately avoided.
            // ponytail: bounded discovery finds late open shadow roots; stylesheet signatures
            // catch silent CSSOM edits. Closed roots require a separate page-world bridge.
            scanTimer = setInterval(poll, 3000);
        }
        sendToChildren();
    }
    window.addEventListener('message', event => {
        if (event.data?.type === 'lean-page-theme' && window !== window.top && event.source === window.parent) apply(event.data.theme);
        if (event.data?.type === 'lean-page-theme-ready') {
            for (let i = 0; i < window.frames.length; i++) {
                if (event.source === window.frames[i]) event.source.postMessage({type: 'lean-page-theme', theme}, '*');
            }
        }
    });
    globalThis.LeanPageTheme = {
        apply,
        // Diagnostics contain role counts and colors, never page text or URLs.
        inspect: () => ({generation, pending: dirty.size + scanning.length, nodes: records.size,
            roles: [...records.values()].reduce((counts, record) => {
                counts[record.role] = (counts[record.role] || 0) + 1; return counts;
            }, {}), palette: [...palette.keys()]})
    };
    if (window !== window.top) window.parent.postMessage({type: 'lean-page-theme-ready'}, '*');
})();

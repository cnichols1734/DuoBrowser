/* DuoBrowser Reader: bounded, read-only extraction in an isolated world. */
(() => {
    const root = document.querySelector('article') || document.querySelector('main,[role="main"]');
    if (!root) return null;
    const blocks = [], excluded = 'nav,aside,footer,form,button,input,textarea,select,script,style,template,noscript,[hidden],[aria-hidden="true"],[contenteditable]';
    if (root.closest(excluded + ',header') || !root.getClientRects().length) return null;
    let visited = 0, characters = 0, images = 0, headline = '';
    const full = () => visited >= 5000 || blocks.length >= 300 || characters >= 100000;
    const hidden = node => {
        if (node.matches(excluded)) return true;
        if (node.tagName === 'HEADER' && !(root.tagName === 'ARTICLE' && root.contains(node))) return true;
        const style = getComputedStyle(node);
        return style.display === 'none' || style.visibility === 'hidden' || style.visibility === 'collapse';
    };
    const textBlock = (kind, text) => {
        const value = text.replace(/\s+/g, ' ').trim().slice(0, 8000);
        if (!value || full()) return;
        blocks.push({kind, text: value});
        characters += value.length;
    };
    const imageBlock = node => {
        if (images >= 40 || full()) return;
        const address = (node.currentSrc || node.getAttribute('src') || '').trim();
        if (!address) return;
        let url;
        try { url = new URL(address, document.baseURI); } catch { return; }
        if (!['http:', 'https:'].includes(url.protocol) || url.username || url.password || url.href.length > 8192) return;
        const rect = node.getBoundingClientRect();
        const width = Math.round(node.naturalWidth || Number(node.getAttribute('width')) || rect.width);
        const height = Math.round(node.naturalHeight || Number(node.getAttribute('height')) || rect.height);
        // Exclude tracking pixels and tiny decorative marks, without requiring an image to have downloaded.
        if (width < 48 || height < 32 || width > 20000 || height > 20000) return;
        blocks.push({kind: 'image', url: url.href, alt: (node.getAttribute('alt') || '').slice(0, 1024), width, height});
        images++;
    };
    const semantic = node => /^(H[1-6]|P|LI|BLOCKQUOTE|PRE|FIGCAPTION)$/.test(node.tagName);
    const kindFor = node => /^H/.test(node.tagName) ? 'heading' : node.closest('figcaption') ? 'caption' : 'paragraph';
    function walk(node, depth = 0) {
        if (full() || depth > 80 || node.nodeType !== Node.ELEMENT_NODE) return;
        visited++;
        if (hidden(node)) return;
        if (node.tagName === 'IMG') { imageBlock(node); return; }
        if (semantic(node)) {
            const hasNestedBlocks = node.querySelector('h1,h2,h3,h4,h5,h6,p,li,blockquote,pre,figcaption');
            if (!hasNestedBlocks && node.querySelector('input,textarea,select,button,script,style,template,noscript,[contenteditable]')) return;
            // Flush direct text around nested blocks and images, preserving source order without duplicates.
            let text = '';
            const firstBlock = blocks.length;
            const kind = kindFor(node);
            function inline(child, level) {
                if (full() || level > 80) return;
                visited++;
                if (child.nodeType === Node.TEXT_NODE) { text += (child.nodeValue || '').slice(0, Math.max(0, 8000 - text.length)); return; }
                if (child.nodeType !== Node.ELEMENT_NODE || hidden(child)) return;
                if (semantic(child)) {
                    textBlock(kind, text); text = ''; walk(child, level + 1); return;
                }
                if (child.tagName === 'IMG') {
                    textBlock(kind, text); text = ''; imageBlock(child); return;
                }
                if (child.tagName === 'BR') text += ' ';
                for (const item of child.childNodes) inline(item, level + 1);
            }
            for (const child of node.childNodes) inline(child, depth + 1);
            textBlock(kind, text);
            if (node.tagName === 'H1' && !headline) {
                const candidate = blocks.slice(firstBlock).filter(block => block.kind === 'heading').map(block => block.text).join(' ');
                if (candidate && candidate.length <= 512) headline = candidate;
            }
            return;
        }
        for (const child of node.children) walk(child, depth + 1);
    }
    walk(root);
    if (characters < 200 || blocks.filter(block => block.kind !== 'image').length < 2) return null;
    return {title: headline || (document.title || '').slice(0, 512), blocks};
})()

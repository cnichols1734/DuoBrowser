/* DuoBrowser Reader: read-only, bounded, text-only extraction in an isolated world. */
(() => {
    const root = document.querySelector('article') || document.querySelector('main,[role="main"]');
    if (!root) return null;
    const blocks = [];
    const walker = document.createTreeWalker(root, NodeFilter.SHOW_ELEMENT);
    let node = root, visited = 0, characters = 0;
    while (node && visited++ < 5000 && blocks.length < 300 && characters < 100000) {
        if (/^(H[1-6]|P|LI|BLOCKQUOTE|PRE)$/.test(node.tagName) &&
            !node.closest('nav,aside,header,footer,form,button,[hidden],[aria-hidden="true"],[contenteditable]')) {
            const style = getComputedStyle(node);
            if (style.display !== 'none' && style.visibility !== 'hidden' && node.getClientRects().length) {
                // Avoid collecting container text twice when a list/quote contains paragraphs.
                if (!node.querySelector('p,li,blockquote,pre,script,style,template,noscript,input,textarea,select,button,[contenteditable],[hidden],[aria-hidden="true"]')) {
                    const text = (node.textContent || '').replace(/\s+/g, ' ').trim().slice(0, 8000);
                    if (text) {
                        blocks.push({kind: /^H/.test(node.tagName) ? 'heading' : 'paragraph', text});
                        characters += text.length;
                    }
                }
            }
        }
        node = walker.nextNode();
    }
    if (characters < 200 || blocks.length < 2) return null;
    return {title: (document.title || '').slice(0, 512), blocks};
})()

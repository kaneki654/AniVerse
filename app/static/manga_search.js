const mangaSearchInput = document.getElementById('manga-search-input');
const mangaSuggestions = document.getElementById('manga-suggestions');
let mangaDebounceTimeout;

if (mangaSearchInput && mangaSuggestions) {
    mangaSearchInput.addEventListener('input', (e) => {
        const query = e.target.value.trim();
        
        // Hide if empty
        if (!query) {
            mangaSuggestions.style.display = 'none';
            mangaSuggestions.innerHTML = '';
            return;
        }

        // Debounce
        clearTimeout(mangaDebounceTimeout);
        mangaDebounceTimeout = setTimeout(async () => {
            try {
                // Fetch suggestions from our backend proxy
                const response = await fetch(`/manga/search/suggestion?q=${encodeURIComponent(query)}`);
                const data = await response.json();
                
                if (data.results && data.results.length > 0) {
                    renderMangaSuggestions(data.results, query);
                } else {
                    renderNoResults(query);
                }
            } catch (error) {
                console.error('Error fetching manga suggestions:', error);
                // Silently fail or show minimal error
                mangaSuggestions.style.display = 'none'; 
            }
        }, 400); // 400ms debounce
    });

    // Close on click outside
    document.addEventListener('click', (e) => {
        if (!mangaSearchInput.contains(e.target) && !mangaSuggestions.contains(e.target)) {
            mangaSuggestions.style.display = 'none';
        }
    });
    
    // Close on Escape
    mangaSearchInput.addEventListener('keydown', (e) => {
        if (e.key === 'Escape') {
            mangaSuggestions.style.display = 'none';
        }
    });
}

function renderMangaSuggestions(results, query) {
    let html = results.map(manga => {
        const tags = manga.genres ? manga.genres.slice(0, 2).join(' · ') : '';
        const statusClass = (manga.status || '').toLowerCase();
        
        return `
        <a href="/manga/${manga.id}" class="manga-suggestion-item">
            <img src="${`/manga/proxy?url=${encodeURIComponent(manga.image)}`}" alt="${manga.title}" class="manga-suggestion-img" onerror="this.src='/static/placeholder.jpg'">
            <div class="manga-suggestion-info">
                <h5>${manga.title}</h5>
                <div class="manga-suggestion-meta">
                    <span>${tags}</span>
                    <span class="manga-status-badge ${statusClass}">${manga.status || 'Unknown'}</span>
                </div>
            </div>
        </a>
        `;
    }).join('');

    // Add "See all results" link
    html += `
    <a href="/manga/search?q=${encodeURIComponent(query)}" class="manga-suggestion-item" style="justify-content: center; color: #e50914; font-weight: bold;">
        🔍 See all results for "${query}"
    </a>
    `;

    mangaSuggestions.innerHTML = html;
    mangaSuggestions.style.display = 'block';
}

function renderNoResults(query) {
    mangaSuggestions.innerHTML = `
    <div class="manga-suggestion-item" style="cursor: default;">
        <div class="manga-suggestion-info" style="text-align: center; color: #aaa;">
            No manga found for "${query}"
        </div>
    </div>
    <a href="/manga/search?q=${encodeURIComponent(query)}" class="manga-suggestion-item" style="justify-content: center; color: #e50914; font-weight: bold;">
        🔍 Search anyway
    </a>
    `;
    mangaSuggestions.style.display = 'block';
}

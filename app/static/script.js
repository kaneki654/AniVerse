const searchInput = document.getElementById('search-input');
const suggestionsList = document.getElementById('search-suggestions');
let debounceTimeout;

searchInput.addEventListener('input', (e) => {
    const query = e.target.value.trim();
    if (!query) {
        suggestionsList.innerHTML = '';
        return;
    }

    clearTimeout(debounceTimeout);
    debounceTimeout = setTimeout(async () => {
        try {
            const response = await fetch(`/search/suggestion?q=${encodeURIComponent(query)}`);
            const data = await response.json();
            
            if (data.data && data.data.suggestions) {
                renderSuggestions(data.data.suggestions);
            }
        } catch (error) {
            console.error('Error fetching suggestions:', error);
        }
    }, 300);
});

function renderSuggestions(suggestions) {
    if (!suggestions.length) {
        suggestionsList.innerHTML = '';
        return;
    }

    const html = suggestions.map(anime => `
        <div class="suggestion-item" onclick="window.location.href='/anime/${anime.id}'">
            <img src="${anime.poster}" alt="${anime.name}">
            <div class="suggestion-info">
                <h5>${anime.name}</h5>
                <span>${anime.moreInfo[0] || ''}</span>
            </div>
        </div>
    `).join('');

    suggestionsList.innerHTML = html;
    suggestionsList.style.display = 'block';
}

document.addEventListener('click', (e) => {
    if (!suggestionsList.contains(e.target) && e.target !== searchInput) {
        suggestionsList.style.display = 'none';
    }
});

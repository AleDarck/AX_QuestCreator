'use strict';

let allQuests    = [];
let selectedId   = null;
let isEditMode   = false;
let deliveryItems = [];
let rewardItems  = [];
let oxItems = [];

// ─── NUI MESSAGES ───────────────────────────────────────────

window.addEventListener('message', (e) => {
    const { action } = e.data;
    if (action === 'openCreator') {
        allQuests = e.data.quests || [];
        oxItems = e.data.items || [];
        showPanel();
        renderQuestList();
        fetchFactions();
    } else if (action === 'factionsList') {
        populateFactions(e.data.factions || []);
    } else if (action === 'forceClose') {
        hideAll();
    } else if (['questCreated','questUpdated','questDeleted'].includes(action)) {
        // Lista se recarga sola vía OpenCreatorNUI
    } else if (action === 'openDelivery') {
        openDeliveryModal(e.data);
    } else if (action === 'updateDeliveryProgress') {
        if (e.data.delivered) {
            renderModalItems(e.data.items, e.data.delivered);
        }
    }
});

// ─── PANEL ──────────────────────────────────────────────────

function showPanel() {
    document.getElementById('creator-panel').classList.remove('hidden');
}

function hideAll() {
    document.getElementById('creator-panel').classList.add('hidden');
    resetForm();
}

// ─── QUEST LIST ─────────────────────────────────────────────

function renderQuestList(filter = '') {
    const container = document.getElementById('quest-list');
    const f = filter.toLowerCase();
    const filtered = allQuests.filter(q =>
        q.name.toLowerCase().includes(f) || q.description.toLowerCase().includes(f)
    );

    if (!filtered.length) {
        container.innerHTML = '<div class="list-empty">Sin misiones encontradas</div>';
        return;
    }

    const typeIcon = { DELIVERY: '📦', TERRITORY: '💀' };
    const diffLabel = { easy: 'FÁCIL', medium: 'MEDIA', hard: 'DIFÍCIL', extreme: 'EXTREMA' };

    container.innerHTML = filtered.map(q => `
        <div class="quest-item ${q.id == selectedId ? 'active' : ''} ${!q.is_active ? 'inactive' : ''}"
             onclick="selectQuest(${q.id})">
            <div class="qi-top">
                <span class="qi-name">${escHtml(q.name)}</span>
                <div class="qi-badges">
                    <span class="badge badge-type-${q.type}">${typeIcon[q.type] || q.type}</span>
                    <span class="badge badge-diff-${q.difficulty}">${diffLabel[q.difficulty]}</span>
                </div>
            </div>
            <div class="qi-desc">${escHtml((q.description||'').substring(0,65))}${(q.description||'').length>65?'…':''}</div>
            <div class="qi-status ${q.is_active ? 'on' : 'off'}"></div>
        </div>
    `).join('');
}

// ─── SELECT QUEST ────────────────────────────────────────────

function selectQuest(id) {
    selectedId = id;
    isEditMode = true;
    renderQuestList(document.getElementById('search-input').value);

    const q = allQuests.find(x => x.id == id);
    if (!q) return;

    showForm();

    document.getElementById('f-id').value          = q.id;
    document.getElementById('f-name').value        = q.name;
    document.getElementById('f-description').value = q.description;
    document.getElementById('f-type').value        = q.type;
    document.getElementById('f-difficulty').value  = q.difficulty;
    document.getElementById('f-faction').value     = q.faction_id || '';
    document.getElementById('f-active').checked    = !!q.is_active;
    document.getElementById('active-label').textContent = q.is_active ? 'SÍ' : 'NO';
    document.getElementById('f-cooldown-hours').value = q.cooldown_minutes || 0;  // ← cooldown
    const obj = typeof q.objective_data === 'string' ? JSON.parse(q.objective_data) : q.objective_data;
    const rew = typeof q.rewards === 'string' ? JSON.parse(q.rewards) : q.rewards;

    fillObjective(q.type, obj);

    document.getElementById('f-reward-money').value = rew.money || 0;
    document.getElementById('f-reward-xp').value    = rew.xp    || 0;
    rewardItems = rew.items || [];
    renderRewardItems();

    document.getElementById('btn-delete').classList.remove('hidden');
}

function fillObjective(type, obj) {
    onTypeChange(type);

    if (type === 'DELIVERY') {
        deliveryItems = (obj.items || []).map(i => ({...i}));
        renderDeliveryItems();
    } else if (type === 'TERRITORY') {
        document.getElementById('obj-zone-x').value = obj.zone?.x || 0;
        document.getElementById('obj-zone-y').value = obj.zone?.y || 0;
        document.getElementById('obj-zone-z').value = obj.zone?.z || 0;
        document.getElementById('obj-zone-r').value = obj.zone?.radius || 80;
        document.getElementById('obj-kills').value  = obj.kills_required || 50;
    }
}

// ─── NUEVA MISIÓN ────────────────────────────────────────────

document.getElementById('btn-new-quest').addEventListener('click', () => {
    selectedId = null;
    isEditMode = false;
    resetForm();
    showForm();
    onTypeChange('DELIVERY');
    document.getElementById('btn-delete').classList.add('hidden');
});

// ─── FORM ────────────────────────────────────────────────────

function showForm() {
    document.getElementById('form-placeholder').classList.add('hidden');
    document.getElementById('quest-form').classList.remove('hidden');
}

function resetForm() {
    selectedId   = null;
    deliveryItems = [];
    rewardItems  = [];
    const form = document.getElementById('quest-form');
    form.classList.add('hidden');
    form.reset();
    document.getElementById('form-placeholder').classList.remove('hidden');
    document.getElementById('delivery-items-container').innerHTML = '';
    document.getElementById('reward-items-container').innerHTML   = '';
    document.getElementById('btn-delete').classList.add('hidden');
    document.getElementById('f-id').value = '';
}

function onTypeChange(forced) {
    const type = forced || document.getElementById('f-type').value;
    if (!forced) document.getElementById('f-type').value = type;

    document.getElementById('obj-delivery').classList.toggle('hidden',  type !== 'DELIVERY');
    document.getElementById('obj-territory').classList.toggle('hidden', type !== 'TERRITORY');
}

// ─── DELIVERY ITEMS ──────────────────────────────────────────

function addDeliveryItem() {
    deliveryItems.push({ name: '', amount: 1, label: '' });
    renderDeliveryItems();
}

function removeDeliveryItem(i) {
    deliveryItems.splice(i, 1);
    renderDeliveryItems();
}

function renderDeliveryItems() {
    const c = document.getElementById('delivery-items-container');
    if (!deliveryItems.length) {
        c.innerHTML = '<div class="list-empty" style="padding:10px 0">Sin items configurados</div>';
        return;
    }
    c.innerHTML = deliveryItems.map((item, i) => `
        <div class="delivery-item-row">
            <div class="form-group">
                <label>NOMBRE (ox_inventory)</label>
                <input type="text" id="di-name-${i}" value="${escHtml(item.name)}" placeholder="Buscar item..."
                    onchange="deliveryItems[${i}].name=this.value">
            </div>
            <div class="form-group">
                <label>CANTIDAD</label>
                <input type="number" min="1" value="${item.amount}"
                    onchange="deliveryItems[${i}].amount=parseInt(this.value)||1">
            </div>
            <div class="form-group">
                <label>ETIQUETA</label>
                <input type="text" value="${escHtml(item.label)}" placeholder="ej: Chatarra"
                    onchange="deliveryItems[${i}].label=this.value">
            </div>
            <button type="button" class="btn-remove-point" onclick="removeDeliveryItem(${i})">✕</button>
        </div>
    `).join('');
    deliveryItems.forEach((_, i) => createItemInput(`di-name-${i}`, i, 'deliveryItems', 'name'));
}

// ─── REWARD ITEMS ────────────────────────────────────────────

function addRewardItem() {
    rewardItems.push({ name: '', amount: 1 });
    renderRewardItems();
}

function removeRewardItem(i) {
    rewardItems.splice(i, 1);
    renderRewardItems();
}

function renderRewardItems() {
    const c = document.getElementById('reward-items-container');
    c.innerHTML = rewardItems.map((item, i) => `
        <div class="delivery-item-row">
            <div class="form-group">
                <label>ÍTEM (ox_inventory)</label>
                <input type="text" id="ri-name-${i}" value="${escHtml(item.name)}" placeholder="Buscar item..."
                    onchange="rewardItems[${i}].name=this.value">
            </div>
            <div class="form-group">
                <label>CANTIDAD</label>
                <input type="number" min="1" value="${item.amount}"
                    onchange="rewardItems[${i}].amount=parseInt(this.value)||1">
            </div>
            <button type="button" class="btn-remove-point" onclick="removeRewardItem(${i})">✕</button>
        </div>
    `).join('');
    rewardItems.forEach((_, i) => createItemInput(`ri-name-${i}`, i, 'rewardItems', 'name'));
}

// ─── TOGGLE ──────────────────────────────────────────────────

document.getElementById('f-active').addEventListener('change', function() {
    document.getElementById('active-label').textContent = this.checked ? 'SÍ' : 'NO';
});

// ─── RECOPILAR DATOS ─────────────────────────────────────────

function collectFormData() {
    const type = document.getElementById('f-type').value;
    let objectiveData = {};
    if (type === 'DELIVERY') {
        objectiveData.items = deliveryItems.map(i => ({
            name:   i.name.trim(),
            amount: parseInt(i.amount) || 1,
            label:  i.label.trim() || i.name.trim()
        }));
    } else if (type === 'TERRITORY') {
        objectiveData.zone = {
            x:      parseFloat(document.getElementById('obj-zone-x').value) || 0,
            y:      parseFloat(document.getElementById('obj-zone-y').value) || 0,
            z:      parseFloat(document.getElementById('obj-zone-z').value) || 0,
            radius: parseFloat(document.getElementById('obj-zone-r').value) || 80,
        };
        objectiveData.kills_required = parseInt(document.getElementById('obj-kills').value) || 50;
    }
    return {
        id:             document.getElementById('f-id').value,
        name:           document.getElementById('f-name').value.trim(),
        description:    document.getElementById('f-description').value.trim(),
        type,
        difficulty:     document.getElementById('f-difficulty').value,
        faction_id:     document.getElementById('f-faction').value,
        is_active:      document.getElementById('f-active').checked,
        cooldown_minutes: parseInt(document.getElementById('f-cooldown-hours').value) || 0,
        objective_data: objectiveData,
        rewards: {
            money: parseInt(document.getElementById('f-reward-money').value) || 0,
            xp:    parseInt(document.getElementById('f-reward-xp').value)    || 0,
            items: rewardItems.filter(i => i.name.trim() !== '')
        }
    };
}

function validateForm(data) {
    if (!data.name) { alert('El nombre es requerido.'); return false; }
    if (data.type === 'DELIVERY' && (!data.objective_data.items || !data.objective_data.items.length)) {
        alert('Agrega al menos un item requerido para la entrega.'); return false;
    }
    if (data.type === 'DELIVERY') {
        for (const item of data.objective_data.items) {
            if (!item.name) { alert('Todos los items deben tener nombre.'); return false; }
        }
    }
    return true;
}

function fillCurrentCoords() {
    fetchNUI('getPlayerCoords', {}).then(r => r.json()).then(coords => {
        document.getElementById('obj-zone-x').value = coords.x;
        document.getElementById('obj-zone-y').value = coords.y;
        document.getElementById('obj-zone-z').value = coords.z;
    });
}

// ─── ACCIONES ────────────────────────────────────────────────

document.getElementById('btn-save').addEventListener('click', () => {
    const data = collectFormData();
    if (!validateForm(data)) return;
    if (isEditMode && data.id) {
        fetchNUI('updateQuest', data);
    } else {
        fetchNUI('createQuest', data);
    }
});

document.getElementById('btn-delete').addEventListener('click', () => {
    const id = document.getElementById('f-id').value;
    if (!id) return;
    if (!confirm('¿Eliminar esta misión permanentemente?')) return;
    fetchNUI('deleteQuest', { id: parseInt(id) });
    resetForm();
});

document.getElementById('btn-cancel').addEventListener('click', () => {
    resetForm();
    selectedId = null;
    renderQuestList(document.getElementById('search-input').value);
});

document.getElementById('btn-close').addEventListener('click', () => {
    fetchNUI('closeCreator', {});
    hideAll();
});

document.getElementById('search-input').addEventListener('input', e => {
    renderQuestList(e.target.value);
});

// ─── FACCIONES ───────────────────────────────────────────────

function fetchFactions() { fetchNUI('getFactions', {}); }

function populateFactions(factions) {
    const sel = document.getElementById('f-faction');
    const all = sel.options[0];
    sel.innerHTML = '';
    sel.appendChild(all);
    factions.forEach(f => {
        const opt = document.createElement('option');
        opt.value = f.name;
        opt.textContent = f.label || f.name;
        sel.appendChild(opt);
    });
}

// ─── UTILS ───────────────────────────────────────────────────

function fetchNUI(action, data) {
    return fetch(`https://AX_QuestCreator/${action}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(data)
    });
}

function escHtml(str) {
    if (!str) return '';
    return String(str).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
}

// ─── DELIVERY MODAL ──────────────────────────────────────────

let currentDeliveryInstanceId = null;

window.addEventListener('message', (e) => {
    // Este handler ya existe, solo agrega el case dentro del switch:
    // action === 'openDelivery' → openDeliveryModal(e.data)
});

function openDeliveryModal(data) {
    currentDeliveryInstanceId = data.instanceId;

    document.getElementById('modal-npc-label').textContent  = data.npcLabel.toUpperCase();
    document.getElementById('modal-quest-name').textContent = data.questName;

    renderModalItems(data.items, data.delivered);

    document.getElementById('delivery-modal').classList.remove('hidden');
}

function renderModalItems(items, delivered) {
    const container = document.getElementById('modal-items-list');
    const allDone   = items.every(i => (delivered[i.name] || 0) >= i.amount);

    container.innerHTML = items.map(item => {
        const done    = delivered[item.name] || 0;
        const pct     = Math.min(Math.round((done / item.amount) * 100), 100);
        const isComplete = done >= item.amount;

        // Ruta de icono ox_inventory
        const iconUrl = `nui://ox_inventory/web/images/${item.name}.png`;

        return `
        <div class="delivery-item ${isComplete ? 'complete' : ''}">
            <div class="item-icon">
                <img src="${iconUrl}" alt="${item.name}"
                    onerror="this.style.display='none';this.nextElementSibling.style.display='flex'">
                <div class="item-icon-fallback" style="display:none">📦</div>
            </div>
            <div class="item-info">
                <div class="item-label">${escHtml(item.label || item.name)}</div>
                <div class="item-name-small">${escHtml(item.name)}</div>
            </div>
            <div class="item-progress">
                <div class="item-amounts">
                    <span class="done ${isComplete ? '' : ''}">${done}</span>
                    <span class="slash"> / </span>
                    <span class="total">${item.amount}</span>
                </div>
                <div class="item-bar-wrap">
                    <div class="item-bar-fill ${isComplete ? 'full' : ''}" style="width:${pct}%"></div>
                </div>
            </div>
        </div>
        `;
    }).join('');

    // Deshabilitar botón si ya está todo completo
    document.getElementById('modal-deliver-btn').disabled = allDone;
    document.getElementById('modal-deliver-btn').textContent = allDone ? '✓ COMPLETADO' : 'ENTREGAR MATERIALES';
}

function closeDeliveryModal() {
    document.getElementById('delivery-modal').classList.add('hidden');
    fetchNUI('closeDelivery', {});
}

document.getElementById('modal-close').addEventListener('click', closeDeliveryModal);

document.getElementById('modal-deliver-btn').addEventListener('click', () => {
    if (!currentDeliveryInstanceId) return;
    fetchNUI('deliverItems', { instanceId: currentDeliveryInstanceId });
    document.getElementById('delivery-modal').classList.add('hidden');
});

function createItemInput(inputId, index, arrayName, fieldName) {
    const input = document.getElementById(inputId);
    if (!input) return;

    // Crear wrapper y dropdown
    const wrapper = document.createElement('div');
    wrapper.className = 'item-autocomplete-wrapper';
    input.parentNode.insertBefore(wrapper, input);
    wrapper.appendChild(input);

    const dropdown = document.createElement('div');
    dropdown.className = 'item-dropdown hidden';
    wrapper.appendChild(dropdown);

    input.addEventListener('input', () => {
        const val = input.value.toLowerCase().trim();
        if (!val || val.length < 2) { dropdown.classList.add('hidden'); return; }

        const matches = oxItems.filter(i =>
            i.name.toLowerCase().includes(val) || i.label.toLowerCase().includes(val)
        ).slice(0, 8);

        if (!matches.length) { dropdown.classList.add('hidden'); return; }

        dropdown.innerHTML = matches.map(item => `
            <div class="item-suggestion" onclick="selectItemSuggestion('${inputId}', '${item.name}', '${escHtml(item.label)}', ${index}, '${arrayName}', '${fieldName}')">
                <div class="suggestion-icon">
                    <img src="nui://ox_inventory/web/images/${item.name}.png"
                        onerror="this.style.display='none';this.nextElementSibling.style.display='flex'"
                        style="width:24px;height:24px;object-fit:contain">
                    <span style="display:none;font-size:14px">📦</span>
                </div>
                <div class="suggestion-info">
                    <span class="suggestion-label">${escHtml(item.label)}</span>
                    <span class="suggestion-name">${item.name}</span>
                </div>
            </div>
        `).join('');

        dropdown.classList.remove('hidden');
    });

    // Cerrar al hacer click fuera
    document.addEventListener('click', (e) => {
        if (!wrapper.contains(e.target)) dropdown.classList.add('hidden');
    });
}

function selectItemSuggestion(inputId, name, label, index, arrayName, fieldName) {
    document.getElementById(inputId).value = name;
    document.querySelector(`#${inputId}`).closest('.item-autocomplete-wrapper').querySelector('.item-dropdown').classList.add('hidden');

    if (arrayName === 'deliveryItems') {
        deliveryItems[index][fieldName] = name;
        if (!deliveryItems[index].label) deliveryItems[index].label = label;
        renderDeliveryItems();
    } else if (arrayName === 'rewardItems') {
        rewardItems[index][fieldName] = name;
        renderRewardItems();
    }
}
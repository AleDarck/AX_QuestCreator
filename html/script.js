// ============================================================
//  AX_QuestCreator | nui/script.js
//  Comunicación NUI ↔ FiveM + lógica del Creator Panel
// ============================================================

'use strict';

// ─── ESTADO ─────────────────────────────────────────────────

let allQuests     = [];
let selectedId    = null;
let repairPoints  = [];
let rewardItems   = [];
let isEditMode    = false;

// ─── NUI MESSAGE HANDLER ────────────────────────────────────

window.addEventListener('message', (event) => {
    const { action } = event.data;

    switch (action) {
        case 'openCreator':
            allQuests = event.data.quests || [];
            showCreatorPanel();
            renderQuestList();
            fetchFactions();
            break;

        case 'factionsList':
            populateFactionDropdown(event.data.factions || []);
            break;

        case 'questCreated':
        case 'questUpdated':
        case 'questDeleted':
            // La lista se recargará automáticamente vía OpenCreatorNUI
            break;

        case 'forceClose':
            hideAll();
            break;
    }
});

// ─── PANEL VISIBILITY ───────────────────────────────────────

function showCreatorPanel() {
    document.getElementById('creator-panel').classList.remove('hidden');
}

function hideAll() {
    document.getElementById('creator-panel').classList.add('hidden');
    resetForm();
}

// ─── RENDER QUEST LIST ──────────────────────────────────────

function renderQuestList(filter = '') {
    const container = document.getElementById('quest-list');
    const filtered  = allQuests.filter(q =>
        q.name.toLowerCase().includes(filter.toLowerCase()) ||
        q.description.toLowerCase().includes(filter.toLowerCase())
    );

    if (filtered.length === 0) {
        container.innerHTML = '<div class="list-empty">Sin misiones encontradas</div>';
        return;
    }

    const typeLabels = { ELIMINATE: '☠', COLLECT: '📦', DEFEND: '🛡', REPAIR: '🔧' };
    const diffLabel  = { easy: 'FÁCIL', medium: 'MEDIA', hard: 'DIFÍCIL', extreme: 'EXTREMA' };

    container.innerHTML = filtered.map(q => `
        <div class="quest-item ${q.id == selectedId ? 'active' : ''} ${!q.is_active ? 'inactive' : ''}"
             onclick="selectQuest(${q.id})">
            <div class="qi-top">
                <span class="qi-name">${escHtml(q.name)}</span>
                <div class="qi-badges">
                    <span class="badge badge-type-${q.type}">${typeLabels[q.type] || q.type}</span>
                    <span class="badge badge-diff-${q.difficulty}">${diffLabel[q.difficulty] || q.difficulty}</span>
                </div>
            </div>
            <div class="qi-desc">${escHtml(q.description.substring(0, 60))}${q.description.length > 60 ? '…' : ''}</div>
            <div class="qi-status ${q.is_active ? 'on' : 'off'}"></div>
        </div>
    `).join('');
}

// ─── SELECCIONAR MISIÓN PARA EDITAR ─────────────────────────

function selectQuest(id) {
    selectedId = id;
    isEditMode = true;
    renderQuestList(document.getElementById('search-input').value);

    const quest = allQuests.find(q => q.id == id);
    if (!quest) return;

    showForm();

    // Llenar campos básicos
    document.getElementById('f-id').value          = quest.id;
    document.getElementById('f-name').value        = quest.name;
    document.getElementById('f-description').value = quest.description;
    document.getElementById('f-type').value        = quest.type;
    document.getElementById('f-difficulty').value  = quest.difficulty;
    document.getElementById('f-faction').value     = quest.faction_id || '';
    document.getElementById('f-active').checked    = !!quest.is_active;
    document.getElementById('active-label').textContent = quest.is_active ? 'SÍ' : 'NO';
    document.getElementById('f-min-players').value = quest.min_players;
    document.getElementById('f-max-players').value = quest.max_players;
    document.getElementById('f-time-limit').value  = quest.time_limit || '';
    document.getElementById('f-cooldown').value    = quest.cooldown_minutes;

    // Objective data
    const obj = typeof quest.objective_data === 'string'
        ? JSON.parse(quest.objective_data) : quest.objective_data;

    fillObjectiveFields(quest.type, obj);

    // Rewards
    const rew = typeof quest.rewards === 'string'
        ? JSON.parse(quest.rewards) : quest.rewards;

    document.getElementById('f-reward-money').value = rew.money || 0;
    rewardItems = rew.items || [];
    renderRewardItems();

    // Mostrar botón eliminar
    document.getElementById('btn-delete').classList.remove('hidden');
}

function fillObjectiveFields(type, obj) {
    onTypeChange(type); // Mostrar la sección correcta

    if (obj.zone) {
        document.getElementById('obj-zone-x').value = obj.zone.x || 0;
        document.getElementById('obj-zone-y').value = obj.zone.y || 0;
        document.getElementById('obj-zone-z').value = obj.zone.z || 0;
        document.getElementById('obj-zone-r').value = obj.zone.radius || 50;
    }

    if (type === 'ELIMINATE') {
        document.getElementById('obj-elim-amount').value = obj.amount || 10;
    } else if (type === 'COLLECT') {
        document.getElementById('obj-collect-item').value   = obj.item || '';
        document.getElementById('obj-collect-amount').value = obj.amount || 5;
    } else if (type === 'DEFEND') {
        document.getElementById('obj-defend-duration').value = obj.duration_seconds || 300;
        document.getElementById('obj-defend-minpl').value    = obj.min_players_inside || 2;
    } else if (type === 'REPAIR') {
        document.getElementById('obj-repair-time').value = obj.interact_time || 10000;
        repairPoints = (obj.points || []).map(p => ({ ...p }));
        renderRepairPoints();
    }
}

// ─── NUEVA MISIÓN ────────────────────────────────────────────

document.getElementById('btn-new-quest').addEventListener('click', () => {
    selectedId = null;
    isEditMode = false;
    resetForm();
    showForm();
    document.getElementById('btn-delete').classList.add('hidden');
    onTypeChange('ELIMINATE');
});

// ─── FORMULARIO ──────────────────────────────────────────────

function showForm() {
    document.getElementById('form-placeholder').classList.add('hidden');
    document.getElementById('quest-form').classList.remove('hidden');
}

function resetForm() {
    selectedId = null;
    repairPoints = [];
    rewardItems  = [];

    const form = document.getElementById('quest-form');
    form.classList.add('hidden');
    form.reset();

    document.getElementById('form-placeholder').classList.remove('hidden');
    document.getElementById('repair-points-container').innerHTML = '';
    document.getElementById('reward-items-container').innerHTML  = '';
    document.getElementById('btn-delete').classList.add('hidden');
    document.getElementById('f-id').value = '';
}

// ─── TIPO → SECCIONES DINÁMICAS ─────────────────────────────

function onTypeChange(forcedType) {
    const type = forcedType || document.getElementById('f-type').value;
    if (!forcedType) document.getElementById('f-type').value = type;

    const hasZone   = ['ELIMINATE','COLLECT','DEFEND'].includes(type);
    const showElim  = type === 'ELIMINATE';
    const showColl  = type === 'COLLECT';
    const showDef   = type === 'DEFEND';
    const showRep   = type === 'REPAIR';

    document.getElementById('obj-zone-section').classList.toggle('hidden', !hasZone);
    document.getElementById('obj-eliminate').classList.toggle('hidden', !showElim);
    document.getElementById('obj-collect').classList.toggle('hidden', !showColl);
    document.getElementById('obj-defend').classList.toggle('hidden', !showDef);
    document.getElementById('obj-repair').classList.toggle('hidden', !showRep);
}

// ─── REPAIR POINTS ───────────────────────────────────────────

function addRepairPoint() {
    repairPoints.push({ x: 0, y: 0, z: 0, label: '' });
    renderRepairPoints();
}

function removeRepairPoint(idx) {
    repairPoints.splice(idx, 1);
    renderRepairPoints();
}

function renderRepairPoints() {
    const container = document.getElementById('repair-points-container');
    container.innerHTML = repairPoints.map((p, i) => `
        <div class="repair-point" id="rp-${i}">
            <div class="form-group"><label>X</label><input type="number" step="0.1" value="${p.x}" onchange="repairPoints[${i}].x=parseFloat(this.value)"></div>
            <div class="form-group"><label>Y</label><input type="number" step="0.1" value="${p.y}" onchange="repairPoints[${i}].y=parseFloat(this.value)"></div>
            <div class="form-group"><label>Z</label><input type="number" step="0.1" value="${p.z}" onchange="repairPoints[${i}].z=parseFloat(this.value)"></div>
            <div class="form-group"><label>ETIQUETA</label><input type="text" value="${escHtml(p.label)}" placeholder="Ej: Generador A" onchange="repairPoints[${i}].label=this.value"></div>
            <button type="button" class="btn-remove-point" onclick="removeRepairPoint(${i})">✕</button>
        </div>
    `).join('');
}

// ─── REWARD ITEMS ────────────────────────────────────────────

function addRewardItem() {
    rewardItems.push({ name: '', amount: 1 });
    renderRewardItems();
}

function removeRewardItem(idx) {
    rewardItems.splice(idx, 1);
    renderRewardItems();
}

function renderRewardItems() {
    const container = document.getElementById('reward-items-container');
    container.innerHTML = rewardItems.map((item, i) => `
        <div class="reward-item">
            <div class="form-group">
                <label>ÍTEM (ox_inventory name)</label>
                <input type="text" value="${escHtml(item.name)}" placeholder="ej: bandage" onchange="rewardItems[${i}].name=this.value">
            </div>
            <div class="form-group">
                <label>CANTIDAD</label>
                <input type="number" min="1" value="${item.amount}" onchange="rewardItems[${i}].amount=parseInt(this.value)||1">
            </div>
            <button type="button" class="btn-remove-point" onclick="removeRewardItem(${i})">✕</button>
        </div>
    `).join('');
}

// ─── TOGGLE ACTIVO ───────────────────────────────────────────

document.getElementById('f-active').addEventListener('change', function () {
    document.getElementById('active-label').textContent = this.checked ? 'SÍ' : 'NO';
});

// ─── RECOPILAR DATOS DEL FORMULARIO ─────────────────────────

function collectFormData() {
    const type = document.getElementById('f-type').value;

    // Construir objective_data
    let objectiveData = {};

    if (type !== 'REPAIR') {
        objectiveData.zone = {
            x:      parseFloat(document.getElementById('obj-zone-x').value) || 0,
            y:      parseFloat(document.getElementById('obj-zone-y').value) || 0,
            z:      parseFloat(document.getElementById('obj-zone-z').value) || 0,
            radius: parseFloat(document.getElementById('obj-zone-r').value) || 50,
        };
    }

    if (type === 'ELIMINATE') {
        objectiveData.amount = parseInt(document.getElementById('obj-elim-amount').value) || 10;
    } else if (type === 'COLLECT') {
        objectiveData.item   = document.getElementById('obj-collect-item').value.trim();
        objectiveData.amount = parseInt(document.getElementById('obj-collect-amount').value) || 5;
        objectiveData.drop_on_kill = false;
    } else if (type === 'DEFEND') {
        objectiveData.duration_seconds  = parseInt(document.getElementById('obj-defend-duration').value) || 300;
        objectiveData.min_players_inside = parseInt(document.getElementById('obj-defend-minpl').value) || 2;
    } else if (type === 'REPAIR') {
        objectiveData.interact_time = parseInt(document.getElementById('obj-repair-time').value) || 10000;
        objectiveData.points = repairPoints.map(p => ({
            x: parseFloat(p.x) || 0,
            y: parseFloat(p.y) || 0,
            z: parseFloat(p.z) || 0,
            label: p.label || ''
        }));
    }

    const timeLimitVal = document.getElementById('f-time-limit').value;

    return {
        id:              document.getElementById('f-id').value,
        name:            document.getElementById('f-name').value.trim(),
        description:     document.getElementById('f-description').value.trim(),
        type:            type,
        difficulty:      document.getElementById('f-difficulty').value,
        faction_id:      document.getElementById('f-faction').value,
        min_players:     parseInt(document.getElementById('f-min-players').value) || 1,
        max_players:     parseInt(document.getElementById('f-max-players').value) || 10,
        time_limit:      timeLimitVal !== '' ? parseInt(timeLimitVal) : '',
        cooldown_minutes: parseInt(document.getElementById('f-cooldown').value) || 60,
        is_active:       document.getElementById('f-active').checked,
        objective_data:  objectiveData,
        rewards: {
            money: parseInt(document.getElementById('f-reward-money').value) || 0,
            items: rewardItems.filter(i => i.name.trim() !== '')
        }
    };
}

function validateForm(data) {
    if (!data.name) { alert('El nombre de la misión es requerido.'); return false; }
    if (!data.type)  { alert('El tipo de misión es requerido.'); return false; }

    if (data.type === 'REPAIR' && data.objective_data.points.length === 0) {
        alert('Agrega al menos un punto de reparación.'); return false;
    }
    if (data.type === 'COLLECT' && !data.objective_data.item) {
        alert('El nombre del ítem es requerido para misiones COLLECT.'); return false;
    }
    return true;
}

// ─── GUARDAR ─────────────────────────────────────────────────

document.getElementById('btn-save').addEventListener('click', () => {
    const data = collectFormData();
    if (!validateForm(data)) return;

    if (isEditMode && data.id) {
        fetchNUI('updateQuest', data);
    } else {
        fetchNUI('createQuest', data);
    }
});

// ─── ELIMINAR ────────────────────────────────────────────────

document.getElementById('btn-delete').addEventListener('click', () => {
    const id = document.getElementById('f-id').value;
    if (!id) return;
    if (!confirm('¿Eliminar esta misión permanentemente?')) return;
    fetchNUI('deleteQuest', { id: parseInt(id) });
    resetForm();
});

// ─── CANCELAR ────────────────────────────────────────────────

document.getElementById('btn-cancel').addEventListener('click', () => {
    resetForm();
    selectedId = null;
    renderQuestList(document.getElementById('search-input').value);
});

// ─── CERRAR ──────────────────────────────────────────────────

document.getElementById('btn-close').addEventListener('click', () => {
    fetchNUI('closeCreator', {});
    hideAll();
});

// ─── SEARCH ──────────────────────────────────────────────────

document.getElementById('search-input').addEventListener('input', (e) => {
    renderQuestList(e.target.value);
});

// ─── FACCIONES ───────────────────────────────────────────────

function fetchFactions() {
    fetchNUI('getFactions', {});
}

function populateFactionDropdown(factions) {
    const select = document.getElementById('f-faction');
    // Mantener la opción "Todas"
    const allOption = select.options[0];
    select.innerHTML = '';
    select.appendChild(allOption);

    factions.forEach(f => {
        const opt = document.createElement('option');
        opt.value       = f.name;
        opt.textContent = f.label || f.name;
        select.appendChild(opt);
    });
}

// ─── UTILIDADES ─────────────────────────────────────────────

function fetchNUI(action, data) {
    return fetch(`https://AX_QuestCreator/${action}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(data)
    });
}

function escHtml(str) {
    if (!str) return '';
    return String(str)
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;');
}
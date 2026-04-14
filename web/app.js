import { initializeApp } from "https://www.gstatic.com/firebasejs/10.12.5/firebase-app.js";
import {
    collection,
    doc,
    getDocs,
    getFirestore,
    limit,
    orderBy,
    query,
    serverTimestamp,
    setDoc,
} from "https://www.gstatic.com/firebasejs/10.12.5/firebase-firestore.js";

const BOARD_SIZE = 15;
const POLL_INTERVAL_MS = 1200;
const HISTORY_LIMIT = 8;
const FIRESTORE_COLLECTION = "gomoku_games";

const firebaseConfig = {
    apiKey: "AIzaSyA9rc8l4GIE0vdM-e0Qa-YtN1iqbiMCuBY",
    authDomain: "introduction-to-computation.firebaseapp.com",
    projectId: "introduction-to-computation",
    storageBucket: "introduction-to-computation.firebasestorage.app",
    messagingSenderId: "751826795764",
    appId: "1:751826795764:web:2a64f1dbcc122ee3cdb2a1",
};

const state = {
    mode: "local",
    game: null,
    roomId: "",
    playerToken: "",
    pendingMove: null,
    busy: false,
    message: "",
    heroStatus: "检查中",
    pollTimer: null,
    db: null,
    firebaseStatus: "Firebase 未配置",
    history: [],
    historyBusy: false,
    lastSavedGameKey: "",
};

const elements = {
    heroMeta: document.getElementById("heroMeta"),
    board: document.getElementById("board"),
    boardHint: document.getElementById("boardHint"),
    statusList: document.getElementById("statusList"),
    modeTabs: document.getElementById("modeTabs"),
    restartButton: document.getElementById("restartButton"),
    lanPanel: document.getElementById("lanPanel"),
    createRoomButton: document.getElementById("createRoomButton"),
    joinRoomButton: document.getElementById("joinRoomButton"),
    roomIdInput: document.getElementById("roomIdInput"),
    roomIdValue: document.getElementById("roomIdValue"),
    roomConnectionValue: document.getElementById("roomConnectionValue"),
    messagePanel: document.getElementById("messagePanel"),
    firebaseStatus: document.getElementById("firebaseStatus"),
    historyList: document.getElementById("historyList"),
    historyEmpty: document.getElementById("historyEmpty"),
    refreshHistoryButton: document.getElementById("refreshHistoryButton"),
};

function boardAt(board, x, y) {
    return board?.[y]?.[x] ?? 0;
}

function isSameCell(a, b) {
    return Boolean(a && b && a.x === b.x && a.y === b.y);
}

function canInteract() {
    if (!state.game || state.busy || state.game.finished) {
        return false;
    }
    if (state.mode === "lan") {
        return state.game.canMove === true && state.game.connectionStatus === "Connected";
    }
    return true;
}

function modeLabel(mode) {
    if (mode === "ai") return "人机";
    if (mode === "lan") return "局域网";
    return "本地双人";
}

function playerLabel(player) {
    if (player === "Black") return "黑方";
    if (player === "White") return "白方";
    return "-";
}

function resultLabel(result) {
    if (result === "BlackWin") return "黑方胜";
    if (result === "WhiteWin") return "白方胜";
    if (result === "Draw") return "平局";
    return "进行中";
}

function connectionLabel(game) {
    if (state.mode !== "lan") {
        return "单机";
    }
    if (!game) {
        return "空闲";
    }
    if (game.connectionStatus === "Connected") {
        return "双方已连接";
    }
    if (game.connectionStatus === "Waiting") {
        return "等待对手加入";
    }
    return game.connectionStatus || "未知";
}

function lastMoveLabel(move) {
    if (!move) {
        return "无";
    }
    return `${move.step} 手 · (${move.x + 1}, ${move.y + 1}) · ${playerLabel(move.stone)}`;
}

function boardHint() {
    if (!state.game) {
        return state.mode === "lan" ? "创建或加入房间后开始对局。" : "点击“重新开始”或切换模式开始对局。";
    }
    if (state.mode === "lan" && state.game.connectionStatus !== "Connected") {
        return "房间已建立，等待第二位玩家加入。";
    }
    if (state.game.finished) {
        return "对局已结束，可点击“重新开始”开启新局。";
    }
    if (state.mode === "lan" && state.game.canMove !== true) {
        return "当前不是你的回合，等待对手落子。";
    }
    return "点击棋盘向后端提交落子坐标。";
}

function isFirebaseConfigured() {
    return Object.values(firebaseConfig).every((value) => typeof value === "string" && value.length > 0 && !value.startsWith("YOUR_"));
}

function hashText(text) {
    let hash = 0;
    for (let index = 0; index < text.length; index += 1) {
        hash = (hash * 31 + text.charCodeAt(index)) >>> 0;
    }
    return hash.toString(36);
}

function buildFinishedGameKey(game) {
    const signature = JSON.stringify({
        mode: game.mode || state.mode,
        roomId: game.roomId || "",
        result: game.gameResult,
        step: game.lastMove?.step ?? 0,
        board: game.board,
    });
    return `game_${hashText(signature)}`;
}

function serializeBoard(board) {
    if (!Array.isArray(board)) {
        return [];
    }
    return board.map((row) => Array.isArray(row) ? row.join(",") : "");
}

function formatTimestamp(value) {
    if (!value) {
        return "时间同步中";
    }

    const date = typeof value.toDate === "function" ? value.toDate() : new Date(value);
    if (Number.isNaN(date.getTime())) {
        return "时间未知";
    }

    return new Intl.DateTimeFormat("zh-CN", {
        year: "numeric",
        month: "2-digit",
        day: "2-digit",
        hour: "2-digit",
        minute: "2-digit",
    }).format(date);
}

function updateGame(game) {
    state.game = game;
    if (!game || !game.finished) {
        state.lastSavedGameKey = "";
        return;
    }
    void persistFinishedGame(game);
}

function showMessage(message) {
    state.message = message;
    render();
}

function clearMessage() {
    state.message = "";
}

async function request(path, options = {}) {
    const response = await fetch(path, {
        headers: {
            "Content-Type": "application/json",
            ...(options.headers || {}),
        },
        ...options,
    });

    const payload = await response.json();
    if (!response.ok || payload.code !== 0) {
        const error = new Error(payload.message || "request failed");
        error.payload = payload;
        throw error;
    }
    return payload.data;
}

async function checkHealth() {
    try {
        await request("/api/health", { method: "GET" });
        state.heroStatus = "后端在线";
    } catch (_) {
        state.heroStatus = "后端不可达";
    }
    render();
}

async function loadHistory() {
    if (!state.db) {
        render();
        return;
    }

    state.historyBusy = true;
    render();

    try {
        const historyQuery = query(
            collection(state.db, FIRESTORE_COLLECTION),
            orderBy("completedAt", "desc"),
            limit(HISTORY_LIMIT),
        );
        const snapshot = await getDocs(historyQuery);
        state.history = snapshot.docs.map((record) => ({
            id: record.id,
            ...record.data(),
        }));
        state.firebaseStatus = "Firestore 已连接";
    } catch (error) {
        state.firebaseStatus = "Firestore 读取失败";
        showMessage(`读取对局记录失败：${error.message}`);
    } finally {
        state.historyBusy = false;
        render();
    }
}

async function persistFinishedGame(game) {
    if (!state.db || !game?.finished) {
        return;
    }

    const gameKey = buildFinishedGameKey(game);
    if (state.lastSavedGameKey === gameKey) {
        return;
    }
    state.lastSavedGameKey = gameKey;

    const payload = {
        mode: game.mode || state.mode,
        modeLabel: modeLabel(game.mode || state.mode),
        gameResult: game.gameResult,
        gameResultLabel: resultLabel(game.gameResult),
        moveCount: game.lastMove?.step ?? 0,
        roomId: game.roomId || null,
        playerStone: game.playerStone || null,
        connectionStatus: game.connectionStatus || null,
        lastMove: game.lastMove || null,
        boardRows: serializeBoard(game.board),
        completedAtClient: Date.now(),
        completedAt: serverTimestamp(),
    };

    try {
        await setDoc(doc(state.db, FIRESTORE_COLLECTION, gameKey), payload, { merge: true });
        state.firebaseStatus = "最近一局已同步到 Firestore";
        await loadHistory();
    } catch (error) {
        state.lastSavedGameKey = "";
        state.firebaseStatus = "Firestore 写入失败";
        showMessage(`保存对局失败：${error.message}`);
        render();
    }
}

async function setupFirebase() {
    if (!isFirebaseConfigured()) {
        state.firebaseStatus = "请先在 web/app.js 中填写 Firebase 配置";
        render();
        return;
    }

    try {
        const app = initializeApp(firebaseConfig);
        state.db = getFirestore(app);
        state.firebaseStatus = "Firestore 已连接";
        render();
        await loadHistory();
    } catch (error) {
        state.firebaseStatus = "Firebase 初始化失败";
        showMessage(`Firebase 初始化失败：${error.message}`);
    }
}

async function startMode(mode) {
    clearMessage();
    state.busy = true;
    render();

    try {
        if (mode === "local") {
            updateGame(await request("/api/local/start", { method: "POST", body: "{}" }));
        } else if (mode === "ai") {
            updateGame(await request("/api/ai/start", { method: "POST", body: "{}" }));
        } else {
            updateGame(null);
            state.roomId = "";
            state.playerToken = "";
        }
        if (mode !== "lan") {
            stopPolling();
        }
    } catch (error) {
        showMessage(error.message);
    } finally {
        state.busy = false;
        state.pendingMove = null;
        render();
    }
}

async function switchMode(mode) {
    state.mode = mode;
    state.pendingMove = null;
    if (mode !== "lan") {
        state.roomId = "";
        state.playerToken = "";
    }
    if (mode === "lan") {
        stopPolling();
        updateGame(null);
        clearMessage();
        render();
        return;
    }
    await startMode(mode);
}

async function submitMove(x, y) {
    if (!canInteract()) {
        return;
    }

    state.busy = true;
    state.pendingMove = { x, y };
    clearMessage();
    render();

    try {
        if (state.mode === "local") {
            updateGame(await request("/api/local/move", {
                method: "POST",
                body: JSON.stringify({ x, y }),
            }));
        } else if (state.mode === "ai") {
            updateGame(await request("/api/ai/move", {
                method: "POST",
                body: JSON.stringify({ x, y }),
            }));
        } else {
            updateGame(await request("/api/room/move", {
                method: "POST",
                body: JSON.stringify({
                    roomId: state.roomId,
                    playerToken: state.playerToken,
                    x,
                    y,
                }),
            }));
        }
    } catch (error) {
        showMessage(error.message);
        if (error.payload?.data) {
            updateGame(error.payload.data);
        }
    } finally {
        state.busy = false;
        state.pendingMove = null;
        render();
    }
}

async function restartGame() {
    clearMessage();

    if (state.mode === "lan") {
        if (!state.roomId || !state.playerToken) {
            showMessage("请先创建或加入房间。");
            return;
        }
        state.busy = true;
        render();
        try {
            updateGame(await request("/api/room/restart", {
                method: "POST",
                body: JSON.stringify({
                    roomId: state.roomId,
                    playerToken: state.playerToken,
                }),
            }));
        } catch (error) {
            showMessage(error.message);
        } finally {
            state.busy = false;
            state.pendingMove = null;
            render();
        }
        return;
    }

    await startMode(state.mode);
}

async function createRoom() {
    clearMessage();
    state.busy = true;
    render();

    try {
        const data = await request("/api/room/create", { method: "POST", body: "{}" });
        state.roomId = data.roomId;
        state.playerToken = data.playerToken;
        updateGame(data);
        startPolling();
    } catch (error) {
        showMessage(error.message);
    } finally {
        state.busy = false;
        render();
    }
}

async function joinRoom() {
    const roomId = elements.roomIdInput.value.trim();
    if (!roomId) {
        showMessage("请输入 roomId。");
        return;
    }

    clearMessage();
    state.busy = true;
    render();

    try {
        const data = await request("/api/room/join", {
            method: "POST",
            body: JSON.stringify({ roomId }),
        });
        state.roomId = data.roomId;
        state.playerToken = data.playerToken;
        updateGame(data);
        startPolling();
    } catch (error) {
        showMessage(error.message);
    } finally {
        state.busy = false;
        render();
    }
}

async function refreshRoomState(showError = false) {
    if (!state.roomId || !state.playerToken) {
        return;
    }

    try {
        const data = await request("/api/room/state", {
            method: "POST",
            body: JSON.stringify({
                roomId: state.roomId,
                playerToken: state.playerToken,
            }),
        });
        updateGame(data);
    } catch (error) {
        if (showError) {
            showMessage(error.message);
        }
    } finally {
        render();
    }
}

function startPolling() {
    stopPolling();
    state.pollTimer = window.setInterval(() => {
        refreshRoomState(false);
    }, POLL_INTERVAL_MS);
}

function stopPolling() {
    if (state.pollTimer) {
        window.clearInterval(state.pollTimer);
        state.pollTimer = null;
    }
}

function renderBoard() {
    elements.board.replaceChildren();

    for (let y = 0; y < BOARD_SIZE; y += 1) {
        for (let x = 0; x < BOARD_SIZE; x += 1) {
            const cell = document.createElement("button");
            const value = boardAt(state.game?.board, x, y);
            const clickable = value === 0 && canInteract();
            const pending = isSameCell(state.pendingMove, { x, y });
            const lastMove = isSameCell(state.game?.lastMove, { x, y });

            cell.type = "button";
            cell.className = "board-cell";
            cell.disabled = !clickable;
            cell.setAttribute("aria-label", `第 ${x + 1} 列，第 ${y + 1} 行`);
            if (x === 0) cell.classList.add("is-first-col");
            if (x === BOARD_SIZE - 1) cell.classList.add("is-last-col");
            if (y === 0) cell.classList.add("is-first-row");
            if (y === BOARD_SIZE - 1) cell.classList.add("is-last-row");

            if (clickable) {
                cell.classList.add("is-clickable");
            }
            if (pending) {
                cell.classList.add("is-pending");
            }

            const lineH = document.createElement("span");
            lineH.className = "cell-line cell-line--h";
            cell.appendChild(lineH);

            const lineV = document.createElement("span");
            lineV.className = "cell-line cell-line--v";
            cell.appendChild(lineV);

            const hoverDot = document.createElement("span");
            hoverDot.className = "cell-hover";
            cell.appendChild(hoverDot);

            cell.addEventListener("click", () => submitMove(x, y));

            if (value !== 0 || pending) {
                const stone = document.createElement("div");
                const stoneClass = value === 2 ? "stone stone--white" : "stone stone--black";
                stone.className = stoneClass;

                if (value === 0) {
                    stone.classList.add("stone--preview");
                    if (state.game?.currentPlayer === "White") {
                        stone.classList.remove("stone--black");
                        stone.classList.add("stone--white");
                    }
                }

                if (lastMove && value !== 0) {
                    stone.classList.add("stone--last");
                }

                if (pending && value === 0 && state.game?.currentPlayer === "White") {
                    stone.classList.remove("stone--black");
                    stone.classList.add("stone--white");
                }

                cell.appendChild(stone);
            }

            elements.board.appendChild(cell);
        }
    }
}

function renderStatus() {
    const items = [
        ["模式", modeLabel(state.mode)],
        ["当前玩家", playerLabel(state.game?.currentPlayer)],
        ["对局结果", resultLabel(state.game?.gameResult)],
        ["连接状态", connectionLabel(state.game)],
        ["最后一步", lastMoveLabel(state.game?.lastMove)],
    ];

    if (state.mode === "lan") {
        items.push(["我的执子", playerLabel(state.game?.playerStone)]);
    }

    elements.statusList.innerHTML = items.map(([label, value]) => `
        <div>
            <dt>${label}</dt>
            <dd>${value}</dd>
        </div>
    `).join("");
}

function renderTabs() {
    elements.modeTabs.querySelectorAll("[data-mode]").forEach((button) => {
        button.classList.toggle("is-active", button.dataset.mode === state.mode);
        button.disabled = state.busy;
    });
}

function renderLanPanel() {
    const visible = state.mode === "lan";
    elements.lanPanel.classList.toggle("panel--hidden", !visible);
    elements.roomIdValue.textContent = state.roomId || "未加入";
    elements.roomConnectionValue.textContent = connectionLabel(state.game);
    elements.createRoomButton.disabled = state.busy;
    elements.joinRoomButton.disabled = state.busy;
}

function renderHistory() {
    elements.firebaseStatus.textContent = state.firebaseStatus;
    elements.refreshHistoryButton.disabled = state.historyBusy || !state.db;

    if (state.historyBusy) {
        elements.historyEmpty.hidden = false;
        elements.historyEmpty.textContent = "正在读取 Firestore 对局记录...";
        elements.historyList.replaceChildren();
        return;
    }

    if (state.history.length === 0) {
        elements.historyEmpty.hidden = false;
        elements.historyEmpty.textContent = state.db
            ? "Firestore 中还没有完成的对局记录。"
            : "配置 Firestore 后，这里会显示最近完成的对局。";
        elements.historyList.replaceChildren();
        return;
    }

    elements.historyEmpty.hidden = true;
    elements.historyList.innerHTML = state.history.map((record) => `
        <article class="history-item">
            <strong>${record.gameResultLabel || resultLabel(record.gameResult)}</strong>
            <div class="history-item__meta">
                <span class="history-tag">${record.modeLabel || modeLabel(record.mode)}</span>
                <span class="history-tag">${record.moveCount || 0} 手</span>
                ${record.roomId ? `<span class="history-tag">房间 ${record.roomId}</span>` : ""}
                <span>${formatTimestamp(record.completedAt || record.completedAtClient)}</span>
            </div>
        </article>
    `).join("");
}

function renderButtons() {
    elements.restartButton.disabled = state.busy || (state.mode === "lan" && !state.roomId);
}

function render() {
    elements.heroMeta.textContent = state.heroStatus;
    elements.boardHint.textContent = boardHint();
    elements.messagePanel.textContent = state.message;
    renderTabs();
    renderBoard();
    renderStatus();
    renderLanPanel();
    renderHistory();
    renderButtons();
}

function bindEvents() {
    elements.modeTabs.addEventListener("click", (event) => {
        const button = event.target.closest("[data-mode]");
        if (!button || button.dataset.mode === state.mode) {
            return;
        }
        switchMode(button.dataset.mode);
    });

    elements.restartButton.addEventListener("click", restartGame);
    elements.createRoomButton.addEventListener("click", createRoom);
    elements.joinRoomButton.addEventListener("click", joinRoom);
    elements.refreshHistoryButton.addEventListener("click", loadHistory);
    elements.roomIdInput.addEventListener("keydown", (event) => {
        if (event.key === "Enter") {
            joinRoom();
        }
    });
}

async function init() {
    bindEvents();
    render();
    await setupFirebase();
    void checkHealth();
    await startMode("local");
}

window.addEventListener("beforeunload", stopPolling);
void init();

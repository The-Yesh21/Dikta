/* ===================================================================
   DIKTA — Pacing Engine & Interactive Simulator
   Pure JavaScript Implementation of Dictation Pacing
   =================================================================== */

(function () {
  'use strict';

  // State
  const state = {
    lpm: 48,                  // Letters per minute
    currentPhraseIndex: 0,
    status: 'speaking',       // 'speaking', 'waiting_gap', 'paused'
    timeRemainingMs: 0,
    totalGapMs: 0,
    timerId: null,
    audioCtx: null,
    isMuted: true
  };

  // Phrases dataset matching the pedagogical note
  const phrases = [
    {
      text: "Mitochondria produce adenosine triphosphate,",
      boundary: "Comma boundary · 1.2x pause factor",
      graphemes: 44,
      syntaxFactor: 1.2,
      spelling: [
        { letters: "M · I · T · O", label: "mito" },
        { letters: "C · H · O · N · D · R · I · A", label: "mitochondria" }
      ],
      isHeading: false,
      isDiagram: false
    },
    {
      text: "the primary energy currency of biological cells.",
      boundary: "Period boundary · 1.5x pause factor",
      graphemes: 49,
      syntaxFactor: 1.5,
      spelling: null,
      isHeading: false,
      isDiagram: false
    },
    {
      text: "Heading: Principles of Cellular Respiration.",
      boundary: "Heading boundary · 1.8x pause factor",
      graphemes: 44,
      syntaxFactor: 1.8,
      spelling: null,
      isHeading: true,
      isDiagram: false
    },
    {
      text: "Diagram note: Leave about 8 lines of space to draw it later.",
      boundary: "Diagram space allocation · 8 ruled lines",
      graphemes: 60,
      syntaxFactor: 1.4,
      spelling: null,
      isHeading: false,
      isDiagram: true
    },
    {
      text: "Through glycolysis and oxidative phosphorylation,",
      boundary: "Comma boundary · 1.2x pause factor",
      graphemes: 51,
      syntaxFactor: 1.2,
      spelling: [
        { letters: "G · L · Y · C · O", label: "glyco" },
        { letters: "L · Y · S · I · S", label: "lysis" }
      ],
      isHeading: false,
      isDiagram: false
    },
    {
      text: "glucose is converted into usable chemical ATP.",
      boundary: "Sentence final · 1.5x pause factor",
      graphemes: 45,
      syntaxFactor: 1.5,
      spelling: null,
      isHeading: false,
      isDiagram: false
    }
  ];

  // DOM Elements
  const elPhraseQuote = document.getElementById('phraseQuote');
  const elPhraseBoundary = document.getElementById('phraseBoundary');
  const elPhraseTracker = document.getElementById('phraseTracker');
  const elLpmDisplay = document.getElementById('lpmDisplay');
  const elSpellingBox = document.getElementById('spellingBox');
  const elSpellingChips = document.getElementById('spellingChips');
  const elStateBadge = document.getElementById('stateBadge');
  const elCountdownDigits = document.getElementById('countdownDigits');
  const elProgressBar = document.getElementById('progressBar');
  const elSoundEqualizer = document.getElementById('soundEqualizer');
  const elMetaGraphemes = document.getElementById('metaGraphemes');
  const elMetaSpeed = document.getElementById('metaSpeed');
  const elMetaSyntax = document.getElementById('metaSyntax');
  const elBtnPause = document.getElementById('btnPause');
  const elBtnRepeat = document.getElementById('btnRepeat');
  const elBtnAdvance = document.getElementById('btnAdvance');
  const elBtnSlower = document.getElementById('btnSlower');
  const elBtnFaster = document.getElementById('btnFaster');

  // Math calculation according to the Pacing Engine:
  // gap = ((n_graphemes / writing_speed) / tempo) * syntax_factor
  // writing_speed in graphemes/second = LPM / 60
  function calculateGapSeconds(phrase, lpm) {
    const charsPerSecond = lpm / 60;
    const baseDuration = phrase.graphemes / charsPerSecond;
    const tempo = 0.94; // 12-min session fatigue factor
    return Math.max(2.5, (baseDuration / tempo) * phrase.syntaxFactor);
  }

  // Play subtle synth pulse
  function playBeep(freq = 440, duration = 0.08) {
    try {
      if (!state.audioCtx) {
        state.audioCtx = new (window.AudioContext || window.webkitAudioContext)();
      }
      if (state.audioCtx.state === 'suspended') {
        state.audioCtx.resume();
      }
      const osc = state.audioCtx.createOscillator();
      const gain = state.audioCtx.createGain();
      osc.type = 'sine';
      osc.frequency.setValueAtTime(freq, state.audioCtx.currentTime);
      gain.gain.setValueAtTime(0.04, state.audioCtx.currentTime);
      gain.gain.exponentialRampToValueAtTime(0.001, state.audioCtx.currentTime + duration);
      osc.connect(gain);
      gain.connect(state.audioCtx.destination);
      osc.start();
      osc.stop(state.audioCtx.currentTime + duration);
    } catch (e) {
      // AudioContext unavailable or restricted
    }
  }

  // Render current phrase
  function renderPhrase() {
    const phrase = phrases[state.currentPhraseIndex];
    if (!phrase) return;

    elPhraseQuote.textContent = `"${phrase.text}"`;
    elPhraseBoundary.innerHTML = `<span>●</span> ${phrase.boundary}`;
    elPhraseTracker.textContent = `Phrase ${state.currentPhraseIndex + 1} of ${phrases.length}`;
    elLpmDisplay.textContent = `Pacing locked: ${state.lpm} LPM`;

    // Spelling box
    if (phrase.spelling && phrase.spelling.length > 0) {
      elSpellingBox.style.display = 'block';
      elSpellingChips.innerHTML = phrase.spelling.map(chip => 
        `<div class="spelling-chip">${chip.letters} <span style="opacity:0.75; font-size:0.75rem;">(${chip.label})</span></div>`
      ).join('');
    } else {
      elSpellingBox.style.display = 'none';
      elSpellingChips.innerHTML = '';
    }

    // Telemetry
    if (elMetaGraphemes) elMetaGraphemes.textContent = phrase.graphemes;
    if (elMetaSpeed) elMetaSpeed.textContent = (state.lpm / 60).toFixed(2) + ' w/s';
    if (elMetaSyntax) elMetaSyntax.textContent = phrase.syntaxFactor.toFixed(2) + 'x';
  }

  // Start Speaking phase
  function startSpeaking() {
    state.status = 'speaking';
    clearInterval(state.timerId);

    renderPhrase();

    // UI State
    elStateBadge.innerHTML = `<span class="sound-equalizer animating" id="soundEqualizer">
      <span class="eq-bar"></span><span class="eq-bar"></span><span class="eq-bar"></span><span class="eq-bar"></span><span class="eq-bar"></span>
    </span> Speaking phrase...`;
    elCountdownDigits.textContent = 'Speaking...';
    elProgressBar.style.width = '0%';
    elBtnPause.innerHTML = `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="6" y="4" width="4" height="16"/><rect x="14" y="4" width="4" height="16"/></svg><span>Pause</span>`;

    // Simulate speech playback duration (e.g. 2.0s to 2.4s)
    const speechDurationMs = 2200;
    playBeep(520, 0.12);

    state.timerId = setTimeout(() => {
      startWritingGap();
    }, speechDurationMs);
  }

  // Start Writing Gap countdown
  function startWritingGap() {
    state.status = 'waiting_gap';
    clearInterval(state.timerId);

    const phrase = phrases[state.currentPhraseIndex];
    const gapSec = calculateGapSeconds(phrase, state.lpm);
    state.totalGapMs = gapSec * 1000;
    state.timeRemainingMs = state.totalGapMs;

    elStateBadge.innerHTML = `<span style="display:inline-block; width:8px; height:8px; border-radius:50%; background:var(--gold-accent);"></span> Writing gap active`;
    
    playBeep(660, 0.08);

    const intervalMs = 100;
    state.timerId = setInterval(() => {
      if (state.status !== 'waiting_gap') return;

      state.timeRemainingMs -= intervalMs;

      if (state.timeRemainingMs <= 0) {
        state.timeRemainingMs = 0;
        clearInterval(state.timerId);
        advancePhrase();
      }

      const elapsedMs = state.totalGapMs - state.timeRemainingMs;
      const progressPercent = Math.min(100, (elapsedMs / state.totalGapMs) * 100);
      elProgressBar.style.width = progressPercent.toFixed(1) + '%';
      
      const secondsLeft = (state.timeRemainingMs / 1000).toFixed(1);
      elCountdownDigits.textContent = `${secondsLeft}s remaining`;
    }, intervalMs);
  }

  // Advance to next phrase
  function advancePhrase() {
    clearInterval(state.timerId);
    state.currentPhraseIndex = (state.currentPhraseIndex + 1) % phrases.length;
    startSpeaking();
  }

  // Event Listeners
  if (elBtnPause) {
    elBtnPause.addEventListener('click', () => {
      if (state.status === 'paused') {
        state.status = 'waiting_gap';
        elBtnPause.innerHTML = `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="6" y="4" width="4" height="16"/><rect x="14" y="4" width="4" height="16"/></svg><span>Pause</span>`;
        startWritingGap();
      } else {
        clearInterval(state.timerId);
        state.status = 'paused';
        elBtnPause.innerHTML = `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polygon points="5 3 19 12 5 21 5 3"/></svg><span>Resume</span>`;
        elStateBadge.innerHTML = `<span style="display:inline-block; width:8px; height:8px; border-radius:50%; background:var(--ink-muted);"></span> Paused`;
        elCountdownDigits.textContent = 'Paused';
      }
    });
  }

  if (elBtnRepeat) {
    elBtnRepeat.addEventListener('click', () => {
      startSpeaking();
    });
  }

  if (elBtnAdvance) {
    elBtnAdvance.addEventListener('click', () => {
      // Student is done handwriting, skip remaining writing gap!
      playBeep(880, 0.06);
      advancePhrase();
    });
  }

  if (elBtnSlower) {
    elBtnSlower.addEventListener('click', () => {
      state.lpm = Math.max(25, state.lpm - 3);
      elLpmDisplay.textContent = `Pacing locked: ${state.lpm} LPM`;
      if (state.status === 'waiting_gap') {
        startWritingGap();
      }
    });
  }

  if (elBtnFaster) {
    elBtnFaster.addEventListener('click', () => {
      state.lpm = Math.min(80, state.lpm + 3);
      elLpmDisplay.textContent = `Pacing locked: ${state.lpm} LPM`;
      if (state.status === 'waiting_gap') {
        startWritingGap();
      }
    });
  }

  // Start on load
  document.addEventListener('DOMContentLoaded', () => {
    startSpeaking();
  });
})();

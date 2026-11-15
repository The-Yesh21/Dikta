/* ===================================================================
   DIKTA — Archival Dictation & Open-Motion System
   Pure JavaScript Implementation
   Modules:
   1. Pacing Engine & Live Simulator
   2. Interactive Organic Spring Audio Equalizer
   3. InkWaves Canvas Fluid Simulation (Gold & Burgundy Tints)
   4. Spotlight Dynamic Lighting on Cards
   5. Magnetic Button Physics
   6. Scroll-Triggered Staggered Reveal Animations
   7. Manuscript Scroll Progress & Ambient Cursor Glow
   =================================================================== */

(function () {
  'use strict';

  /* =================================================================
     1. PACING ENGINE & INTERACTIVE SIMULATOR
     ================================================================= */
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
  const elStateBadgeText = document.getElementById('stateBadgeText');
  const elStateStatusDot = document.getElementById('stateStatusDot');
  const elCountdownDigits = document.getElementById('countdownDigits');
  const elProgressBar = document.getElementById('progressBar');
  const elSoundEqualizer = document.getElementById('soundEqualizer');
  const elMetaGraphemes = document.getElementById('metaGraphemes');
  const elMetaSpeed = document.getElementById('metaSpeed');
  const elMetaSyntax = document.getElementById('metaSyntax');
  const elBtnPause = document.getElementById('btnPause');
  const elBtnPauseText = document.getElementById('btnPauseText');
  const elBtnRepeat = document.getElementById('btnRepeat');
  const elBtnAdvance = document.getElementById('btnAdvance');
  const elBtnSlower = document.getElementById('btnSlower');
  const elBtnFaster = document.getElementById('btnFaster');

  // Gap calculation pure math:
  // gap = ((n_graphemes / writing_speed) / tempo) * syntax_factor
  function calculateGapSeconds(phrase, lpm) {
    const charsPerSecond = lpm / 60;
    const baseDuration = phrase.graphemes / charsPerSecond;
    const tempo = 0.94; // 12-min session fatigue factor
    return Math.max(2.5, (baseDuration / tempo) * phrase.syntaxFactor);
  }

  // Play subtle acoustic synth pulse
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

    if (elPhraseQuote) elPhraseQuote.textContent = `"${phrase.text}"`;
    if (elPhraseBoundary) elPhraseBoundary.innerHTML = `<span>●</span> ${phrase.boundary}`;
    if (elPhraseTracker) elPhraseTracker.textContent = `Phrase ${state.currentPhraseIndex + 1} of ${phrases.length}`;
    if (elLpmDisplay) elLpmDisplay.textContent = `Pacing locked: ${state.lpm} LPM`;

    // Spelling box
    if (elSpellingBox && elSpellingChips) {
      if (phrase.spelling && phrase.spelling.length > 0) {
        elSpellingBox.style.display = 'block';
        elSpellingChips.innerHTML = phrase.spelling.map(chip =>
          `<div class="spelling-chip">${chip.letters} <span style="opacity:0.75; font-size:0.75rem;">(${chip.label})</span></div>`
        ).join('');
      } else {
        elSpellingBox.style.display = 'none';
        elSpellingChips.innerHTML = '';
      }
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

    // UI State updates without destroying DOM
    if (elStateBadgeText) elStateBadgeText.textContent = 'Speaking phrase...';
    if (elStateStatusDot) elStateStatusDot.style.display = 'none';
    if (elSoundEqualizer) elSoundEqualizer.style.display = 'inline-flex';
    if (elCountdownDigits) elCountdownDigits.textContent = 'Speaking...';
    if (elProgressBar) elProgressBar.style.width = '0%';
    if (elBtnPauseText) elBtnPauseText.textContent = 'Pause';

    // Trigger organic equalizer speaking animation
    equalizerEngine.setMode('speaking');
    equalizerEngine.triggerRipple(6);

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

    if (elStateBadgeText) elStateBadgeText.textContent = 'Writing gap active';
    if (elStateStatusDot) elStateStatusDot.style.display = 'inline-block';
    equalizerEngine.setMode('gap');

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
      if (elProgressBar) elProgressBar.style.width = progressPercent.toFixed(1) + '%';

      const secondsLeft = (state.timeRemainingMs / 1000).toFixed(1);
      if (elCountdownDigits) elCountdownDigits.textContent = `${secondsLeft}s remaining`;
    }, intervalMs);
  }

  // Advance to next phrase
  function advancePhrase() {
    clearInterval(state.timerId);
    state.currentPhraseIndex = (state.currentPhraseIndex + 1) % phrases.length;
    startSpeaking();
  }

  // Simulator Event Listeners
  if (elBtnPause) {
    elBtnPause.addEventListener('click', () => {
      equalizerEngine.triggerRipple(8);
      if (state.status === 'paused') {
        state.status = 'waiting_gap';
        if (elBtnPauseText) elBtnPauseText.textContent = 'Pause';
        if (elStateBadgeText) elStateBadgeText.textContent = 'Writing gap active';
        if (elStateStatusDot) elStateStatusDot.style.display = 'inline-block';
        equalizerEngine.setMode('gap');
        startWritingGap();
      } else {
        clearInterval(state.timerId);
        state.status = 'paused';
        if (elBtnPauseText) elBtnPauseText.textContent = 'Resume';
        if (elStateBadgeText) elStateBadgeText.textContent = 'Paused';
        if (elStateStatusDot) elStateStatusDot.style.display = 'inline-block';
        if (elCountdownDigits) elCountdownDigits.textContent = 'Paused';
        equalizerEngine.setMode('paused');
      }
    });
  }

  if (elBtnRepeat) {
    elBtnRepeat.addEventListener('click', () => {
      equalizerEngine.triggerRipple(10);
      startSpeaking();
    });
  }

  if (elBtnAdvance) {
    elBtnAdvance.addEventListener('click', () => {
      equalizerEngine.triggerRipple(12);
      playBeep(880, 0.06);
      advancePhrase();
    });
  }

  if (elBtnSlower) {
    elBtnSlower.addEventListener('click', () => {
      equalizerEngine.triggerRipple(7);
      state.lpm = Math.max(25, state.lpm - 3);
      if (elLpmDisplay) elLpmDisplay.textContent = `Pacing locked: ${state.lpm} LPM`;
      if (state.status === 'waiting_gap') {
        startWritingGap();
      }
    });
  }

  if (elBtnFaster) {
    elBtnFaster.addEventListener('click', () => {
      equalizerEngine.triggerRipple(7);
      state.lpm = Math.min(80, state.lpm + 3);
      if (elLpmDisplay) elLpmDisplay.textContent = `Pacing locked: ${state.lpm} LPM`;
      if (state.status === 'waiting_gap') {
        startWritingGap();
      }
    });
  }

  /* =================================================================
     2. INTERACTIVE AUDIO EQUALIZER WITH ORGANIC SPRING PHYSICS
     Ported and elevated for Dictation Simulator
     ================================================================= */
  const equalizerEngine = (function () {
    let bars = [];
    let mode = 'speaking'; // 'speaking', 'gap', 'paused'
    let rafId = null;
    let lastTime = performance.now();

    function init() {
      const container = document.getElementById('soundEqualizer');
      if (!container) return;

      const barElements = container.querySelectorAll('.eq-bar');
      bars = Array.from(barElements).map((el, i) => ({
        el,
        height: 5 + i * 2,
        targetHeight: 5,
        velocity: 0,
        tension: 0.14 + (i % 3) * 0.02,
        damping: 0.72 + (i % 2) * 0.03,
        baseFreq: 0.006 + i * 0.003,
        phase: i * 0.75,
      }));

      // Interactive hover plucking
      container.addEventListener('mouseenter', () => triggerRipple(9));
      container.addEventListener('mousemove', (e) => {
        const rect = container.getBoundingClientRect();
        const normX = Math.min(1, Math.max(0, (e.clientX - rect.left) / rect.width));
        const index = Math.floor(normX * bars.length);
        if (bars[index]) {
          bars[index].velocity += 5;
        }
      });

      const phraseStage = document.getElementById('phraseQuote');
      if (phraseStage) {
        phraseStage.addEventListener('mouseenter', () => triggerRipple(6));
      }

      startLoop();
    }

    function triggerRipple(strength = 8) {
      bars.forEach((b, i) => {
        setTimeout(() => {
          b.velocity += strength + (Math.random() - 0.5) * 3;
        }, i * 35);
      });
    }

    function setMode(newMode) {
      mode = newMode;
    }

    function startLoop() {
      function tick(now) {
        const dt = Math.min(now - lastTime, 40);
        lastTime = now;

        for (let i = 0; i < bars.length; i++) {
          const b = bars[i];

          // Compute biological speech target heights
          if (mode === 'speaking') {
            const syllableWave = Math.sin(now * 0.0055);
            const burst = syllableWave > 0 ? Math.pow(syllableWave, 1.8) * 9 : 1.5;
            const formant = Math.sin(now * b.baseFreq + b.phase) * 3.5;
            b.targetHeight = Math.max(3.5, Math.min(18, 5.5 + burst + formant));
          } else if (mode === 'gap') {
            // Calm resting breath wave during handwriting
            b.targetHeight = 3.5 + Math.sin(now * 0.0022 + b.phase) * 1.2;
          } else {
            // Paused
            b.targetHeight = 3.0;
          }

          // Organic spring physics calculation: F = -k*(x - target) - c*v
          const displacement = b.height - b.targetHeight;
          const force = -b.tension * displacement;
          b.velocity = (b.velocity + force) * b.damping;
          b.height += b.velocity * (dt / 16);

          // Clamping
          b.height = Math.max(2.5, Math.min(22, b.height));
          b.el.style.height = `${b.height.toFixed(1)}px`;
        }

        rafId = requestAnimationFrame(tick);
      }

      rafId = requestAnimationFrame(tick);
    }

    return {
      init,
      triggerRipple,
      setMode
    };
  })();

  /* =================================================================
     3. INKWAVES: CANVAS FLUID SIMULATION
     Ported from InkWaves.tsx and InkParticles.tsx
     Delicate Gold & Burgundy Tints:
     - rgba(197, 160, 89, 0.03) [Antique Gold]
     - rgba(91, 16, 30, 0.02)   [Royal Burgundy]
     ================================================================= */
  function initInkWaves() {
    const canvas = document.getElementById('inkWavesCanvas');
    if (!canvas) return;
    const ctx = canvas.getContext('2d');
    if (!ctx) return;

    let width = 0;
    let height = 0;
    let dpr = 1;

    function resize() {
      dpr = Math.min(window.devicePixelRatio || 1, 1.75);
      width = window.innerWidth;
      height = window.innerHeight;
      canvas.width = Math.floor(width * dpr);
      canvas.height = Math.floor(height * dpr);
      canvas.style.width = width + 'px';
      canvas.style.height = height + 'px';
      ctx.setTransform(1, 0, 0, 1, 0, 0);
      ctx.scale(dpr, dpr);
    }
    resize();
    window.addEventListener('resize', resize, { passive: true });

    const mouse = { x: 0.5, y: 0.5, targetX: 0.5, targetY: 0.5 };
    window.addEventListener('mousemove', (e) => {
      mouse.targetX = e.clientX / window.innerWidth;
      mouse.targetY = e.clientY / window.innerHeight;
    }, { passive: true });

    // Fluid Wave Layers with exact requested gold & burgundy tints
    const layers = [
      { amplitude: 26, frequency: 0.0028, speed: 0.00008, offset: 0, opacity: 0.022, color: '91, 16, 30', yRatio: 0.36, lineWidth: 1.0, blur: 0.6 },
      { amplitude: 44, frequency: 0.0020, speed: 0.00006, offset: Math.PI / 3, opacity: 0.030, color: '197, 160, 89', yRatio: 0.50, lineWidth: 1.4, blur: 0.8 },
      { amplitude: 36, frequency: 0.0034, speed: 0.00010, offset: Math.PI / 2, opacity: 0.020, color: '123, 23, 40', yRatio: 0.64, lineWidth: 1.1, blur: 0.6 },
      { amplitude: 56, frequency: 0.0016, speed: 0.00004, offset: Math.PI, opacity: 0.028, color: '197, 160, 89', yRatio: 0.76, lineWidth: 1.6, blur: 1.0 },
      { amplitude: 22, frequency: 0.0042, speed: 0.00012, offset: Math.PI * 1.4, opacity: 0.018, color: '91, 16, 30', yRatio: 0.88, lineWidth: 0.9, blur: 0.5 },
    ];

    // Drifting Soft Ink Washes
    const washes = [
      { x: width * 0.18, y: height * 0.35, radius: 220, vx: 0.03, vy: -0.015, opacity: 0.024, phase: 0, color: '197, 160, 89' },
      { x: width * 0.82, y: height * 0.52, radius: 260, vx: -0.025, vy: 0.02, opacity: 0.020, phase: 1.6, color: '91, 16, 30' },
      { x: width * 0.44, y: height * 0.74, radius: 200, vx: 0.02, vy: -0.01, opacity: 0.022, phase: 3.2, color: '197, 160, 89' },
      { x: width * 0.70, y: height * 0.22, radius: 240, vx: -0.02, vy: 0.015, opacity: 0.018, phase: 4.4, color: '91, 16, 30' }
    ];

    // Elongated Calligraphic Ink Streaks
    const streaks = [];
    for (let i = 0; i < 22; i++) {
      streaks.push({
        x: Math.random() * width,
        layer: Math.floor(Math.random() * layers.length),
        length: 50 + Math.random() * 130,
        vx: 0.05 + Math.random() * 0.12,
        opacity: Math.random() * 0.035 + 0.018,
        phase: Math.random() * Math.PI * 2,
        yOffset: (Math.random() - 0.5) * 14,
      });
    }

    // Manuscript Paper & Gold Leaf Drifting Dust Particles
    const particles = [];
    for (let i = 0; i < 26; i++) {
      particles.push({
        x: Math.random() * width,
        y: Math.random() * height,
        vx: (Math.random() - 0.5) * 0.16,
        vy: -0.12 - Math.random() * 0.22,
        radius: Math.random() * 2.2 + 0.7,
        color: Math.random() > 0.45 ? '197, 160, 89' : '123, 23, 40',
        opacity: Math.random() * 0.16 + 0.05,
        phase: Math.random() * Math.PI * 2,
      });
    }

    let lastTime = performance.now();
    let time = 0;
    let rafId = null;

    function getWaveY(layer, x, t) {
      const baseY = height * layer.yRatio;
      const mouseInfluence = (mouse.x - 0.5) * 18;
      const wave1 = Math.sin(x * layer.frequency + t * layer.speed * 18 + layer.offset) * layer.amplitude;
      const wave2 = Math.sin(x * layer.frequency * 2.1 + t * layer.speed * 10 + layer.offset) * layer.amplitude * 0.28;
      const wave3 = Math.sin(x * layer.frequency * 0.6 + t * layer.speed * 6) * layer.amplitude * 0.4;
      return baseY + wave1 + wave2 + wave3 + mouseInfluence * layer.yRatio;
    }

    function render(now) {
      const dt = Math.min(now - lastTime, 50);
      lastTime = now;
      time += dt;

      // Mouse position smoothing
      mouse.x += (mouse.targetX - mouse.x) * 0.04;
      mouse.y += (mouse.targetY - mouse.y) * 0.04;

      ctx.clearRect(0, 0, width, height);

      // 1. Draw large fluid ink washes
      for (let i = 0; i < washes.length; i++) {
        const w = washes[i];
        w.x += w.vx * (dt / 16);
        w.y += (w.vy + Math.sin(time * 0.0002 + w.phase) * 0.05) * (dt / 16);
        if (w.x < -w.radius) w.x = width + w.radius;
        if (w.x > width + w.radius) w.x = -w.radius;
        if (w.y < -w.radius) w.y = height + w.radius;
        if (w.y > height + w.radius) w.y = -w.radius;

        const breath = 1 + Math.sin(time * 0.0004 + w.phase) * 0.08;
        const r = w.radius * breath;
        const grad = ctx.createRadialGradient(w.x, w.y, 0, w.x, w.y, r);
        grad.addColorStop(0, `rgba(${w.color}, ${w.opacity})`);
        grad.addColorStop(0.5, `rgba(${w.color}, ${w.opacity * 0.35})`);
        grad.addColorStop(1, `rgba(${w.color}, 0)`);
        ctx.fillStyle = grad;
        ctx.beginPath();
        ctx.arc(w.x, w.y, r, 0, Math.PI * 2);
        ctx.fill();
      }

      // 2. Draw wave layers
      const step = 6;
      for (let l = 0; l < layers.length; l++) {
        const layer = layers[l];

        // Gradient wash beneath wave
        ctx.beginPath();
        ctx.moveTo(0, getWaveY(layer, 0, time));
        for (let x = step; x <= width; x += step) {
          ctx.lineTo(x, getWaveY(layer, x, time));
        }
        ctx.lineTo(width, height);
        ctx.lineTo(0, height);
        ctx.closePath();

        const grad = ctx.createLinearGradient(0, height * layer.yRatio, 0, height);
        grad.addColorStop(0, `rgba(${layer.color}, ${layer.opacity})`);
        grad.addColorStop(0.65, `rgba(${layer.color}, ${layer.opacity * 0.25})`);
        grad.addColorStop(1, `rgba(${layer.color}, 0)`);
        ctx.fillStyle = grad;
        ctx.fill();

        // Wave stroke
        ctx.save();
        ctx.shadowColor = `rgba(${layer.color}, ${layer.opacity * 0.7})`;
        ctx.shadowBlur = layer.blur * 3;
        ctx.beginPath();
        for (let x = 0; x <= width; x += step) {
          const y = getWaveY(layer, x, time);
          if (x === 0) ctx.moveTo(x, y);
          else ctx.lineTo(x, y);
        }
        ctx.strokeStyle = `rgba(${layer.color}, ${layer.opacity * 1.4})`;
        ctx.lineWidth = layer.lineWidth;
        ctx.lineCap = 'round';
        ctx.stroke();
        ctx.restore();
      }

      // 3. Draw calligraphic ink streaks
      for (let i = 0; i < streaks.length; i++) {
        const s = streaks[i];
        const layer = layers[s.layer];
        s.x += s.vx * (dt / 16);
        if (s.x > width + s.length) s.x = -s.length;

        const baseY = getWaveY(layer, s.x + s.length / 2, time);
        const startY = getWaveY(layer, s.x, time) + s.yOffset;
        const endY = getWaveY(layer, s.x + s.length, time) + s.yOffset;
        const midY = baseY + s.yOffset + Math.sin(time * 0.0003 + s.phase) * 3;

        const opacity = s.opacity * (0.7 + Math.sin(time * 0.0006 + s.phase) * 0.3);
        const grad = ctx.createLinearGradient(s.x, startY, s.x + s.length, endY);
        grad.addColorStop(0, `rgba(${layer.color}, 0)`);
        grad.addColorStop(0.5, `rgba(${layer.color}, ${opacity})`);
        grad.addColorStop(1, `rgba(${layer.color}, 0)`);

        ctx.strokeStyle = grad;
        ctx.lineWidth = 0.8;
        ctx.lineCap = 'round';
        ctx.beginPath();
        ctx.moveTo(s.x, startY);
        ctx.quadraticCurveTo(s.x + s.length / 2, midY, s.x + s.length, endY);
        ctx.stroke();
      }

      // 4. Draw gentle drifting manuscript dust & gold particles
      for (let i = 0; i < particles.length; i++) {
        const p = particles[i];
        p.x += p.vx * (dt / 16);
        p.y += p.vy * (dt / 16);
        if (p.y < -10) {
          p.y = height + 10;
          p.x = Math.random() * width;
        }
        if (p.x < -10) p.x = width + 10;
        if (p.x > width + 10) p.x = -10;

        const shimmer = Math.sin(time * 0.002 + p.phase) * 0.3 + 0.7;
        ctx.fillStyle = `rgba(${p.color}, ${p.opacity * shimmer})`;
        ctx.beginPath();
        ctx.arc(p.x, p.y, p.radius, 0, Math.PI * 2);
        ctx.fill();
      }

      rafId = requestAnimationFrame(render);
    }

    // Pause when page is hidden
    document.addEventListener('visibilitychange', () => {
      if (document.hidden) {
        if (rafId) cancelAnimationFrame(rafId);
        rafId = null;
      } else if (!rafId) {
        lastTime = performance.now();
        rafId = requestAnimationFrame(render);
      }
    });

    if (!window.matchMedia('(prefers-reduced-motion: reduce)').matches) {
      rafId = requestAnimationFrame(render);
    }
  }

  /* =================================================================
     4. SPOTLIGHT DYNAMIC LIGHTING ON CARDS
     Ported from SpotlightCard.tsx
     Applies to .spotlight-card, .feature-card, .arch-card, .spec-card, .mockup-sheet, .how-step-card
     ================================================================= */
  function initSpotlightCards() {
    const cards = document.querySelectorAll(
      '.spotlight-card, .feature-card, .arch-card, .spec-card, .mockup-sheet, .compare-card, .pillar-card, .diagram-card, .lang-card, .notebook-card, .download-box, .how-step-card, .how-interactive-banner'
    );

    cards.forEach((card) => {
      // Ensure spotlight overlay exists
      if (!card.querySelector('.card-spotlight')) {
        const spot = document.createElement('div');
        spot.className = 'card-spotlight';
        spot.setAttribute('aria-hidden', 'true');
        card.appendChild(spot);
      }

      card.addEventListener('mousemove', (e) => {
        const rect = card.getBoundingClientRect();
        const x = ((e.clientX - rect.left) / rect.width) * 100;
        const y = ((e.clientY - rect.top) / rect.height) * 100;
        card.style.setProperty('--spotlight-x', `${x.toFixed(2)}%`);
        card.style.setProperty('--spotlight-y', `${y.toFixed(2)}%`);
      }, { passive: true });
    });
  }

  /* =================================================================
     5. MAGNETIC BUTTON PHYSICS
     Ported from MagneticButton.tsx
     Applies to Download APK, simulator controls, and header CTA
     ================================================================= */
  function initMagneticButtons() {
    if (window.matchMedia('(hover: none)').matches) return;

    const buttons = document.querySelectorAll(
      '.magnetic-btn, .btn-primary, .btn-secondary, .ctrl-btn, .header-cta-btn, .download-btn-capsule'
    );

    buttons.forEach((btn) => {
      let currentX = 0;
      let currentY = 0;
      let targetX = 0;
      let targetY = 0;
      let isHovered = false;
      let animId = null;

      const strength = btn.classList.contains('header-cta-btn') ? 0.35 :
                       btn.classList.contains('ctrl-btn') ? 0.28 :
                       btn.classList.contains('btn-primary') || btn.classList.contains('download-btn-capsule') ? 0.32 : 0.3;

      function springLoop() {
        currentX += (targetX - currentX) * 0.16;
        currentY += (targetY - currentY) * 0.16;

        if (Math.abs(targetX - currentX) < 0.05 && Math.abs(targetY - currentY) < 0.05 && !isHovered) {
          currentX = 0;
          currentY = 0;
          btn.style.transform = '';
          animId = null;
          return;
        }

        btn.style.transform = `translate3d(${currentX.toFixed(2)}px, ${currentY.toFixed(2)}px, 0)`;
        animId = requestAnimationFrame(springLoop);
      }

      btn.addEventListener('mousemove', (e) => {
        const rect = btn.getBoundingClientRect();
        const x = e.clientX - rect.left - rect.width / 2;
        const y = e.clientY - rect.top - rect.height / 2;
        targetX = x * strength;
        targetY = y * strength;
        isHovered = true;
        if (!animId) {
          animId = requestAnimationFrame(springLoop);
        }
      });

      btn.addEventListener('mouseleave', () => {
        targetX = 0;
        targetY = 0;
        isHovered = false;
        if (!animId) {
          animId = requestAnimationFrame(springLoop);
        }
      });
    });
  }

  /* =================================================================
     6. SCROLL-TRIGGERED REVEAL ANIMATIONS
     Ported from Reveal.tsx with Staggered Card Thresholds
     ================================================================= */
  function initScrollReveal() {
    const reveals = document.querySelectorAll(
      '.reveal, .reveal-ink, .reveal-scale, .reveal-fade, .reveal-group > *'
    );

    if (window.matchMedia('(prefers-reduced-motion: reduce)').matches) {
      reveals.forEach((el) => el.classList.add('revealed'));
      return;
    }

    const observer = new IntersectionObserver(
      (entries, obs) => {
        entries.forEach((entry) => {
          if (entry.isIntersecting) {
            const el = entry.target;
            // Apply staggered threshold delay for siblings in a grid
            const parent = el.parentElement;
            if (parent && parent.classList.contains('reveal-group')) {
              const index = Array.from(parent.children).indexOf(el);
              el.style.transitionDelay = `${index * 80}ms`;
            }
            el.classList.add('revealed');
            obs.unobserve(el);
          }
        });
      },
      { threshold: 0.12, rootMargin: '0px 0px -30px 0px' }
    );

    reveals.forEach((el) => observer.observe(el));
  }

  /* =================================================================
     7. MANUSCRIPT SCROLL PROGRESS & AMBIENT CURSOR GLOW
     Ported from ScrollProgress.tsx and CursorGlow.tsx
     ================================================================= */
  function initScrollProgress() {
    const bar = document.getElementById('scrollProgressBar');
    if (!bar) return;

    function update() {
      const scrollTop = window.scrollY || document.documentElement.scrollTop;
      const docHeight = document.documentElement.scrollHeight - window.innerHeight;
      const progress = docHeight > 0 ? Math.min(100, Math.max(0, (scrollTop / docHeight) * 100)) : 0;
      bar.style.width = `${progress}%`;
    }

    window.addEventListener('scroll', update, { passive: true });
    update();
  }

  function initCursorGlow() {
    const glow = document.getElementById('cursorGlow');
    if (!glow || window.matchMedia('(hover: none)').matches) return;

    let currentX = -500;
    let currentY = -500;
    let targetX = -500;
    let targetY = -500;
    let raf = null;

    window.addEventListener('mousemove', (e) => {
      targetX = e.clientX;
      targetY = e.clientY;
      if (!raf) {
        raf = requestAnimationFrame(updateGlow);
      }
    }, { passive: true });

    function updateGlow() {
      currentX += (targetX - currentX) * 0.14;
      currentY += (targetY - currentY) * 0.14;
      glow.style.background = `radial-gradient(600px circle at ${currentX.toFixed(1)}px ${currentY.toFixed(1)}px, rgba(197, 160, 89, 0.05), rgba(91, 16, 30, 0.02) 40%, transparent 70%)`;
      glow.style.opacity = '1';

      if (Math.abs(targetX - currentX) > 0.5 || Math.abs(targetY - currentY) > 0.5) {
        raf = requestAnimationFrame(updateGlow);
      } else {
        raf = null;
      }
    }
  }

  /* =================================================================
     8. HOW TO USE INTERACTIVE STEPPER & MOBILE NAVIGATION
     ================================================================= */
  function initHowToUseInteractive() {
    const tabButtons = document.querySelectorAll('.how-tab-btn');
    const stepCards = document.querySelectorAll('.how-step-card');
    const trackProgress = document.getElementById('howTrackProgress');

    function setActiveStep(stepNum) {
      const num = parseInt(stepNum, 10);
      if (isNaN(num) || num < 1 || num > 4) return;

      // Update Tab buttons
      tabButtons.forEach((btn) => {
        const btnStep = parseInt(btn.getAttribute('data-step'), 10);
        const isActive = btnStep === num;
        btn.classList.toggle('active', isActive);
        btn.setAttribute('aria-selected', isActive ? 'true' : 'false');
      });

      // Update Step Cards
      stepCards.forEach((card) => {
        const cardStep = parseInt(card.getAttribute('data-step'), 10);
        card.classList.toggle('active', cardStep === num);
      });

      // Update Track Progress Bar
      if (trackProgress) {
        const percent = (num / 4) * 100;
        trackProgress.style.width = `${percent}%`;
      }
    }

    // Attach click to tab buttons
    tabButtons.forEach((btn) => {
      btn.addEventListener('click', () => {
        const step = btn.getAttribute('data-step');
        setActiveStep(step);
      });
    });

    // Attach click, hover, and focus to step cards
    stepCards.forEach((card) => {
      card.addEventListener('click', () => {
        const step = card.getAttribute('data-step');
        setActiveStep(step);
      });

      card.addEventListener('mouseenter', () => {
        const step = card.getAttribute('data-step');
        setActiveStep(step);
      });

      card.addEventListener('focus', () => {
        const step = card.getAttribute('data-step');
        setActiveStep(step);
      });
    });

    // Step 2 Micro-Interaction: Script Switcher
    const scriptChips = document.querySelectorAll('.rhythm-script-chip');
    const pulseThumb = document.querySelector('.rhythm-pulse-thumb');
    scriptChips.forEach((chip) => {
      chip.addEventListener('click', (e) => {
        e.stopPropagation();
        scriptChips.forEach((c) => c.classList.remove('active'));
        chip.classList.add('active');
        if (pulseThumb) {
          const isDevanagari = chip.textContent.includes('Devanagari');
          pulseThumb.style.left = isDevanagari ? '75%' : '45%';
        }
      });
    });

    // Step 4 Micro-Interaction: Voice Command Chips
    const cmdChips = document.querySelectorAll('.cmd-pill-badge');
    cmdChips.forEach((chip) => {
      chip.addEventListener('click', (e) => {
        e.stopPropagation();
        cmdChips.forEach((c) => c.classList.remove('active'));
        chip.classList.add('active');
      });
    });
  }

  function initMobileMenu() {
    const toggleBtn = document.getElementById('mobileMenuToggle');
    const drawer = document.getElementById('mobileNavDrawer');
    if (!toggleBtn || !drawer) return;

    function toggleMenu(open) {
      const isOpen = open !== undefined ? open : !toggleBtn.classList.contains('open');
      toggleBtn.classList.toggle('open', isOpen);
      toggleBtn.setAttribute('aria-expanded', isOpen ? 'true' : 'false');
      drawer.classList.toggle('open', isOpen);
      drawer.setAttribute('aria-hidden', isOpen ? 'false' : 'true');
    }

    toggleBtn.addEventListener('click', (e) => {
      e.stopPropagation();
      toggleMenu();
    });

    // Close when clicking nav links inside mobile drawer
    const links = drawer.querySelectorAll('.mobile-nav-link');
    links.forEach((link) => {
      link.addEventListener('click', () => {
        toggleMenu(false);
      });
    });

    // Close when clicking outside drawer
    document.addEventListener('click', (e) => {
      if (!drawer.contains(e.target) && !toggleBtn.contains(e.target) && toggleBtn.classList.contains('open')) {
        toggleMenu(false);
      }
    });

    // Close on Escape key
    document.addEventListener('keydown', (e) => {
      if (e.key === 'Escape' && toggleBtn.classList.contains('open')) {
        toggleMenu(false);
        toggleBtn.focus();
      }
    });
  }

  /* =================================================================
     INITIALIZATION ON DOM READY
     ================================================================= */
  document.addEventListener('DOMContentLoaded', () => {
    // 1. Equalizer engine
    equalizerEngine.init();

    // 2. InkWaves background canvas
    initInkWaves();

    // 3. Spotlight dynamic lighting
    initSpotlightCards();

    // 4. Magnetic button physics
    initMagneticButtons();

    // 5. Scroll reveal animations
    initScrollReveal();

    // 6. Manuscript reading progress
    initScrollProgress();

    // 7. Ambient cursor glow
    initCursorGlow();

    // 8. How to Use Interactive Stepper
    initHowToUseInteractive();

    // 9. Mobile Navigation Menu
    initMobileMenu();

    // 10. Start pacing simulator
    startSpeaking();
  });
})();

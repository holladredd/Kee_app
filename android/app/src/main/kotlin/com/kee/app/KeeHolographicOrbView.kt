package com.kee.app

import android.animation.ValueAnimator
import android.content.Context
import android.graphics.*
import android.view.View
import android.view.animation.LinearInterpolator
import kotlin.math.*

/** Overlay states the holographic orb renders distinct animations for. */
enum class OrbState { IDLE, LISTENING, THINKING, SPEAKING, ERROR }

/**
 * Jarvis-inspired holographic Kee orb — drawn natively on Android Canvas.
 * Uses only official Kee brand colours:
 *   Black:        #080808
 *   Warm ivory:   #F3F0E8
 *   Soft grey:    #77736B
 *   Light accent: #D8D2C5
 *
 * Distinct visual behaviour per state:
 * - IDLE:      Gentle breathing, slow orbital rings, subtle particles, low glow.
 * - LISTENING: Bright ivory core, mic-amplitude reactive ripples, outward mesh expansion,
 *              warm ivory listening indicator ring.
 * - THINKING:  Faster rotating orbital rings, counter-rotating particle orbits, champagne pulse.
 * - SPEAKING:  Distinct dual-harmonic speech wave rings + central light pulse driven by
 *              real TTS word-boundary cadence (onRangeStart) with natural decay.
 * - ERROR:     Calm core with subtle muted rose ring.
 */
class KeeHolographicOrbView(context: Context) : View(context) {

    // Official Kee brand palette
    private val cObsidian   = Color.parseColor("#080808")
    private val cCoreDeep   = Color.parseColor("#11100E")
    private val cIvory      = Color.parseColor("#F3F0E8")
    private val cChampagne  = Color.parseColor("#D8D2C5")
    private val cSoftGrey   = Color.parseColor("#77736B")
    private val cMeshLine   = Color.parseColor("#BFB8AE")
    private val cErrorRose  = Color.parseColor("#D97070")

    private var state: OrbState = OrbState.IDLE

    // Real audio-driven amplitudes (0..1)
    private var listeningAmplitude: Float = 0f
    private var smoothedListeningAmp: Float = 0f
    private var speakingTargetAmp: Float = 0f
    private var smoothedSpeakingAmp: Float = 0f
    private var lastSpeakingPulseMs: Long = 0L

    // Animation phase values
    private var pulse = 0f
    private var rotAngle = 0f
    private var meshAngle = 0f
    private var speechWave = 0f

    private val pulseAnim = makeLoopAnimator(2800L, reverse = true) { pulse = it }
    private val rotAnim   = makeLoopAnimator(9000L, reverse = false) { rotAngle = it * 2f * PI.toFloat() }
    private val meshAnim  = makeLoopAnimator(15000L, reverse = false) { meshAngle = it * 2f * PI.toFloat() }
    private val waveAnim  = makeLoopAnimator(1000L, reverse = false) {
        speechWave = it
        // Smoothly track & decay real audio amplitudes on each frame
        smoothedListeningAmp += (listeningAmplitude - smoothedListeningAmp) * 0.35f
        val now = System.currentTimeMillis()
        if (state == OrbState.SPEAKING) {
            // Decay word-boundary impulse naturally between syllables
            if (now - lastSpeakingPulseMs > 180L) {
                speakingTargetAmp *= 0.86f
            }
            smoothedSpeakingAmp += (speakingTargetAmp - smoothedSpeakingAmp) * 0.42f
        } else {
            smoothedSpeakingAmp = 0f
            speakingTargetAmp = 0f
        }
    }

    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val clipPath = Path()
    private val haloPath = Path()
    private val innerExclPath = Path()

    init {
        startAnimators()
    }

    fun setState(newState: OrbState) {
        if (state == newState) return
        state = newState
        if (newState != OrbState.LISTENING) {
            listeningAmplitude = 0f
            smoothedListeningAmp = 0f
        }
        if (newState != OrbState.SPEAKING) {
            speakingTargetAmp = 0f
            smoothedSpeakingAmp = 0f
        }
        applySpeedForState(newState)
        invalidate()
    }

    /** Feed real microphone rmsdB from SpeechRecognizer.onRmsChanged (typically -2..10). */
    fun setListeningAmplitude(rmsdB: Float) {
        listeningAmplitude = ((rmsdB + 2f) / 12f).coerceIn(0f, 1f)
        invalidate()
    }

    /** Feed real TTS word/syllable boundary from UtteranceProgressListener.onRangeStart. */
    fun onTtsWordBoundary(wordLength: Int) {
        if (state != OrbState.SPEAKING) return
        lastSpeakingPulseMs = System.currentTimeMillis()
        // Longer/stressed words produce a slightly stronger speech impulse (0.45..1.0)
        speakingTargetAmp = (0.45f + (wordLength.coerceIn(1, 10) / 10f) * 0.55f).coerceIn(0.45f, 1f)
        invalidate()
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        startAnimators()
    }

    override fun onDetachedFromWindow() {
        super.onDetachedFromWindow()
        pulseAnim.cancel()
        rotAnim.cancel()
        meshAnim.cancel()
        waveAnim.cancel()
    }

    override fun onDraw(canvas: Canvas) {
        if (width == 0 || height == 0) return
        val cx = width / 2f
        val cy = height / 2f
        val base = min(width, height) * 0.27f

        drawAmbientGlow(canvas, cx, cy, base)
        drawMeshGrid(canvas, cx, cy, base)
        drawOrbitalRings(canvas, cx, cy, base)

        when (state) {
            OrbState.LISTENING -> drawListeningRipples(canvas, cx, cy, base)
            OrbState.SPEAKING  -> drawSpeakingHarmonics(canvas, cx, cy, base)
            OrbState.THINKING  -> drawThinkingParticles(canvas, cx, cy, base)
            OrbState.IDLE      -> drawIdleParticles(canvas, cx, cy, base)
            OrbState.ERROR     -> {}
        }

        drawSphere(canvas, cx, cy, base)
        drawSpecularHighlight(canvas, cx, cy, base)

        when (state) {
            OrbState.LISTENING -> drawListeningIndicator(canvas, cx, cy, base)
            OrbState.SPEAKING  -> drawSpeakingCore(canvas, cx, cy, base)
            OrbState.ERROR     -> drawErrorRing(canvas, cx, cy, base)
            else               -> {}
        }
    }

    private fun drawAmbientGlow(canvas: Canvas, cx: Float, cy: Float, base: Float) {
        val ampBoost = when (state) {
            OrbState.LISTENING -> smoothedListeningAmp * 0.22f
            OrbState.SPEAKING  -> smoothedSpeakingAmp * 0.20f
            else               -> 0f
        }
        val radius = base * (1.15f + 0.14f * pulse + ampBoost) * 1.55f
        val alpha = when (state) {
            OrbState.IDLE      -> 0.18f
            OrbState.LISTENING -> 0.34f + smoothedListeningAmp * 0.18f
            OrbState.SPEAKING  -> 0.32f + smoothedSpeakingAmp * 0.16f
            OrbState.THINKING  -> 0.28f
            OrbState.ERROR     -> 0.22f
        }
        val activeColor = activeColor()
        paint.shader = RadialGradient(
            cx, cy, radius,
            intArrayOf(
                withAlpha(activeColor, alpha),
                withAlpha(cChampagne, 0.08f),
                Color.TRANSPARENT
            ),
            floatArrayOf(0.22f, 0.62f, 1f),
            Shader.TileMode.CLAMP
        )
        paint.style = Paint.Style.FILL
        canvas.drawCircle(cx, cy, radius, paint)
        paint.shader = null
    }

    private fun drawMeshGrid(canvas: Canvas, cx: Float, cy: Float, base: Float) {
        val outwardExpand = when (state) {
            OrbState.LISTENING -> 1f + smoothedListeningAmp * 0.18f
            OrbState.SPEAKING  -> 1f + smoothedSpeakingAmp * 0.12f
            else               -> 1f
        }
        val inner = base * 1.0f * outwardExpand
        val halo = base * 1.24f * outwardExpand

        // Inner flowing mesh clipped inside orb
        canvas.save()
        clipPath.reset()
        clipPath.addCircle(cx, cy, inner, Path.Direction.CW)
        canvas.clipPath(clipPath)
        val innerAlpha = if (state == OrbState.LISTENING || state == OrbState.THINKING) 0.28f else 0.20f
        drawRotatedGrid(canvas, cx, cy, inner, rotAngle, cMeshLine, innerAlpha, 0.85f)
        drawRotatedGrid(canvas, cx, cy, inner, -meshAngle * 0.65f, cChampagne, innerAlpha * 0.75f, 0.65f)
        canvas.restore()

        // Outer subtle mesh halo ring
        canvas.save()
        haloPath.reset()
        haloPath.addCircle(cx, cy, halo, Path.Direction.CW)
        innerExclPath.reset()
        innerExclPath.addCircle(cx, cy, inner, Path.Direction.CCW)
        haloPath.op(innerExclPath, Path.Op.DIFFERENCE)
        canvas.clipPath(haloPath)
        drawRotatedGrid(canvas, cx, cy, halo, meshAngle * 0.35f, cMeshLine, 0.11f, 0.55f)
        canvas.restore()
    }

    private fun drawRotatedGrid(
        canvas: Canvas,
        cx: Float,
        cy: Float,
        radius: Float,
        angle: Float,
        color: Int,
        alpha: Float,
        strokeWidth: Float
    ) {
        canvas.save()
        canvas.translate(cx, cy)
        canvas.rotate(Math.toDegrees(angle.toDouble()).toFloat())
        paint.style = Paint.Style.STROKE
        paint.color = withAlpha(color, alpha)
        paint.strokeWidth = strokeWidth

        val spacing = (radius * 0.28f).coerceAtLeast(10f)
        val extent = radius * 1.15f
        val lines = (extent / spacing).toInt() + 1

        for (i in -lines..lines) {
            val d = i * spacing
            canvas.drawLine(d, -extent, d, extent, paint)
            canvas.drawLine(-extent, d, extent, d, paint)
        }
        canvas.restore()
    }

    private fun drawOrbitalRings(canvas: Canvas, cx: Float, cy: Float, base: Float) {
        val reactScale = when (state) {
            OrbState.LISTENING -> 1f + smoothedListeningAmp * 0.16f
            OrbState.SPEAKING  -> 1f + smoothedSpeakingAmp * 0.14f
            else               -> 1f
        }
        val ringRadius = base * 1.18f * reactScale

        // Primary champagne orbital ellipse
        canvas.save()
        canvas.translate(cx, cy)
        canvas.rotate(Math.toDegrees(rotAngle * 0.38).toFloat())
        canvas.scale(1f, 0.38f)
        paint.style = Paint.Style.STROKE
        paint.color = withAlpha(cChampagne, 0.32f + 0.14f * pulse)
        paint.strokeWidth = 1.2f
        canvas.drawCircle(0f, 0f, ringRadius, paint)
        canvas.restore()

        // Secondary soft grey counter-rotating orbital ellipse
        canvas.save()
        canvas.translate(cx, cy)
        canvas.rotate(Math.toDegrees(-meshAngle * 0.28 + PI / 4).toFloat())
        canvas.scale(0.38f, 1f)
        paint.color = withAlpha(cSoftGrey, 0.24f + 0.10f * pulse)
        paint.strokeWidth = 0.9f
        canvas.drawCircle(0f, 0f, ringRadius * 0.96f, paint)
        canvas.restore()

        // Third delicate outer orbital ring in THINKING or SPEAKING
        if (state == OrbState.THINKING || state == OrbState.SPEAKING) {
            canvas.save()
            canvas.translate(cx, cy)
            canvas.rotate(Math.toDegrees(rotAngle * 0.65 - PI / 3).toFloat())
            canvas.scale(0.92f, 0.52f)
            paint.color = withAlpha(cIvory, 0.22f)
            paint.strokeWidth = 0.8f
            canvas.drawCircle(0f, 0f, ringRadius * 1.1f, paint)
            canvas.restore()
        }
    }

    private fun drawIdleParticles(canvas: Canvas, cx: Float, cy: Float, base: Float) {
        paint.style = Paint.Style.FILL
        paint.color = withAlpha(cSoftGrey, 0.45f)
        for (i in 0 until 4) {
            val a = rotAngle * 0.5f + i * (PI.toFloat() / 2f)
            val d = base * (1.22f + 0.04f * sin(pulse * PI.toFloat() + i))
            canvas.drawCircle(cx + d * cos(a), cy + d * sin(a), 1.8f, paint)
        }
    }

    private fun drawListeningRipples(canvas: Canvas, cx: Float, cy: Float, base: Float) {
        val amp = 0.15f + smoothedListeningAmp * 0.85f
        paint.style = Paint.Style.STROKE
        for ((factor, alpha) in listOf(
            Pair(1.14f + 0.22f * amp, 0.24f * amp),
            Pair(1.30f + 0.34f * amp, 0.14f * amp)
        )) {
            paint.strokeWidth = 1.6f
            paint.color = withAlpha(cIvory, alpha)
            canvas.drawCircle(cx, cy, base * factor, paint)
        }
    }

    private fun drawThinkingParticles(canvas: Canvas, cx: Float, cy: Float, base: Float) {
        paint.style = Paint.Style.FILL
        // Outer 5 champagne particles
        paint.color = withAlpha(cChampagne, 0.90f)
        for (i in 0 until 5) {
            val a = rotAngle * 1.2f + i * (2f * PI.toFloat() / 5f)
            val d = base * 1.28f
            canvas.drawCircle(cx + d * cos(a), cy + d * sin(a), 2.8f, paint)
        }
        // Inner 6 warm grey counter-orbit particles
        paint.color = withAlpha(cSoftGrey, 0.65f)
        for (i in 0 until 6) {
            val a = -meshAngle * 1.1f + i * (PI.toFloat() / 3f)
            val d = base * 1.10f
            canvas.drawCircle(cx + d * cos(a), cy + d * sin(a), 1.9f, paint)
        }
    }

    private fun drawSpeakingHarmonics(canvas: Canvas, cx: Float, cy: Float, base: Float) {
        // Distinct from listening: modulated harmonic wave ring around orb driven by TTS cadence
        val amp = smoothedSpeakingAmp
        paint.style = Paint.Style.STROKE
        paint.strokeWidth = 1.5f
        paint.color = withAlpha(cChampagne, 0.35f + 0.45f * amp)

        val segments = 48
        val wavePath = Path()
        for (i in 0..segments) {
            val theta = (i.toFloat() / segments) * 2f * PI.toFloat()
            val harmonic = sin(theta * 4f + speechWave * 2f * PI.toFloat()) * (base * 0.08f * (0.25f + amp))
            val r = base * (1.20f + 0.12f * amp) + harmonic
            val x = cx + r * cos(theta)
            val y = cy + r * sin(theta)
            if (i == 0) wavePath.moveTo(x, y) else wavePath.lineTo(x, y)
        }
        wavePath.close()
        canvas.drawPath(wavePath, paint)
    }

    private fun drawSphere(canvas: Canvas, cx: Float, cy: Float, base: Float) {
        val ampScale = when (state) {
            OrbState.LISTENING -> smoothedListeningAmp * 0.07f
            OrbState.SPEAKING  -> smoothedSpeakingAmp * 0.08f
            else               -> 0f
        }
        val r = base * (0.94f + 0.05f * pulse + ampScale)
        val offX = -0.28f * cos(rotAngle * 0.4f) * r
        val offY = -0.28f * sin(rotAngle * 0.4f) * r
        val active = activeColor()

        paint.shader = RadialGradient(
            cx + offX, cy + offY, r,
            intArrayOf(
                withAlpha(active, 0.90f),
                withAlpha(cChampagne, 0.48f),
                cCoreDeep,
                cObsidian
            ),
            floatArrayOf(0f, 0.34f, 0.72f, 1f),
            Shader.TileMode.CLAMP
        )
        paint.style = Paint.Style.FILL
        canvas.drawCircle(cx, cy, r, paint)
        paint.shader = null
    }

    private fun drawSpecularHighlight(canvas: Canvas, cx: Float, cy: Float, base: Float) {
        val r = base * (0.94f + 0.05f * pulse)
        paint.color = withAlpha(cIvory, 0.24f + 0.10f * pulse)
        paint.style = Paint.Style.FILL
        canvas.drawCircle(cx - r * 0.26f, cy - r * 0.26f, r * 0.20f, paint)
    }

    private fun drawListeningIndicator(canvas: Canvas, cx: Float, cy: Float, base: Float) {
        // Brightening central core + subtle warm ivory listening ring
        val r = base * (0.94f + 0.05f * pulse)
        val coreR = r * (0.28f + 0.18f * smoothedListeningAmp + 0.06f * pulse)
        paint.style = Paint.Style.FILL
        paint.color = withAlpha(cIvory, 0.65f + 0.30f * smoothedListeningAmp)
        canvas.drawCircle(cx, cy, coreR, paint)

        // Subtle warm-ivory listening ring around sphere edge
        paint.style = Paint.Style.STROKE
        paint.strokeWidth = 1.8f
        paint.color = withAlpha(cIvory, 0.55f + 0.35f * smoothedListeningAmp)
        canvas.drawCircle(cx, cy, r * 1.04f, paint)
    }

    private fun drawSpeakingCore(canvas: Canvas, cx: Float, cy: Float, base: Float) {
        // Warm champagne/ivory speech core pulse driven by TTS word boundary
        val r = base * (0.94f + 0.05f * pulse)
        val coreR = r * (0.22f + 0.24f * smoothedSpeakingAmp)
        paint.style = Paint.Style.FILL
        paint.color = withAlpha(cChampagne, 0.55f + 0.40f * smoothedSpeakingAmp)
        canvas.drawCircle(cx, cy, coreR, paint)
    }

    private fun drawErrorRing(canvas: Canvas, cx: Float, cy: Float, base: Float) {
        val r = base * (0.94f + 0.04f * pulse) * 1.06f
        paint.color = withAlpha(cErrorRose, 0.65f)
        paint.style = Paint.Style.STROKE
        paint.strokeWidth = 2.6f
        canvas.drawCircle(cx, cy, r, paint)
    }

    private fun activeColor(): Int = when (state) {
        OrbState.ERROR     -> cErrorRose
        OrbState.THINKING  -> cChampagne
        OrbState.LISTENING -> cIvory
        OrbState.SPEAKING  -> cChampagne
        OrbState.IDLE      -> cIvory
    }

    private fun withAlpha(color: Int, alpha: Float): Int {
        val a = (alpha.coerceIn(0f, 1f) * 255).toInt()
        return Color.argb(a, Color.red(color), Color.green(color), Color.blue(color))
    }

    private fun applySpeedForState(s: OrbState) {
        val (pDur, rDur, mDur) = when (s) {
            OrbState.IDLE      -> Triple(3000L, 11000L, 18000L)
            OrbState.LISTENING -> Triple(1100L,  4500L,  8000L)
            OrbState.THINKING  -> Triple( 700L,  1800L,  3200L)
            OrbState.SPEAKING  -> Triple( 900L,  3200L,  6000L)
            OrbState.ERROR     -> Triple(1800L,  7000L, 14000L)
        }
        setAnimDuration(pulseAnim, pDur)
        setAnimDuration(rotAnim, rDur)
        setAnimDuration(meshAnim, mDur)
    }

    private fun setAnimDuration(anim: ValueAnimator, durationMs: Long) {
        val fraction = anim.animatedFraction
        anim.duration = durationMs
        if (anim.isRunning) {
            anim.setCurrentFraction(fraction)
        }
    }

    private fun startAnimators() {
        listOf(pulseAnim, rotAnim, meshAnim, waveAnim).forEach {
            if (!it.isRunning) it.start()
        }
    }

    private fun makeLoopAnimator(durationMs: Long, reverse: Boolean, onUpdate: (Float) -> Unit): ValueAnimator {
        return ValueAnimator.ofFloat(0f, 1f).apply {
            duration = durationMs
            interpolator = LinearInterpolator()
            repeatMode = if (reverse) ValueAnimator.REVERSE else ValueAnimator.RESTART
            repeatCount = ValueAnimator.INFINITE
            addUpdateListener {
                onUpdate(it.animatedValue as Float)
                invalidate()
            }
        }
    }
}

package io.bazel.kotlin.plugin.jdeps.k2

import org.jetbrains.kotlin.KtSourceFile
import org.jetbrains.kotlin.fir.analysis.checkers.context.CheckerContext
import org.jetbrains.kotlin.fir.declarations.utils.sourceElement
import org.jetbrains.kotlin.fir.resolve.providers.symbolProvider
import org.jetbrains.kotlin.fir.symbols.impl.FirClassLikeSymbol
import org.jetbrains.kotlin.fir.symbols.impl.FirClassSymbol
import org.jetbrains.kotlin.fir.types.ConeKotlinType
import org.jetbrains.kotlin.fir.types.FirTypeRef
import org.jetbrains.kotlin.fir.types.classId
import org.jetbrains.kotlin.fir.types.coneType
import org.jetbrains.kotlin.fir.types.forEachType
import org.jetbrains.kotlin.name.ClassId
import java.io.File
import java.nio.file.Paths

private const val ANONYMOUS = "<anonymous>"

/** The jars one source uses. */
internal class SourceJars {
  /** The jars the source uses explicitly. */
  val explicit: MutableSet<String> = linkedSetOf()

  /** The jars the source needs implicitly, e.g. for a supertype. */
  val implicit: MutableSet<String> = linkedSetOf()
}

/**
 * The jars of the classes the analyzed sources use, by the path of the source using them. A usage
 * outside a source file is recorded under the empty path.
 *
 * @param classpath the classpath of the compilation, which the jar of a class resolves to.
 */
class ClassUsageRecorder(
  classpath: List<String>,
) {
  internal val jarsBySource = linkedMapOf<String, SourceJars>()

  // Create mapping from canonical paths to original classpath paths
  private val canonicalToClasspath = createCanonicalToClasspathMap(classpath)

  // Sources share most of their jars: resolve each jar once.
  private val classpathJars = hashMapOf<String, String>()

  /**
   * The classpath entries of the classes resolved so far, by the class's location. The entry is
   * empty for a class not loaded from a jar.
   */
  private val classpathJarsByClass = hashMapOf<String, String>()

  /**
   * The source file of the last recorded usage. The checkers record the usages of one file after
   * another, so the path of a file is resolved once, not once per usage.
   */
  private var lastSourceFile: KtSourceFile? = null

  /** The jars of [lastSourceFile]. */
  private var lastJars: SourceJars? = null

  /** Records an analyzed source, so that it is listed even if it uses no classes. */
  internal fun recordSource(path: String): SourceJars = jarsBySource.getOrPut(path) { SourceJars() }

  internal fun recordTypeRef(
    typeRef: FirTypeRef,
    context: CheckerContext,
    isExplicit: Boolean = true,
    collectTypeArguments: Boolean = true,
    visited: MutableSet<Pair<ClassId, Boolean>> = mutableSetOf(),
  ) {
    recordConeType(typeRef.coneType, context, isExplicit, collectTypeArguments, visited)
  }

  internal fun recordConeType(
    coneKotlinType: ConeKotlinType,
    context: CheckerContext,
    isExplicit: Boolean = true,
    collectTypeArguments: Boolean = true,
    visited: MutableSet<Pair<ClassId, Boolean>> = mutableSetOf(),
  ) {
    if (collectTypeArguments) {
      coneKotlinType.forEachType(
        action = { coneType ->
          val classId = coneType.classId ?: return@forEachType
          if (ANONYMOUS in classId.toString()) return@forEachType
          context.session.symbolProvider
            .getClassLikeSymbolByClassId(classId)
            ?.let { recordClass(it, context, isExplicit, collectTypeArguments, visited) }
        },
      )
    } else {
      coneKotlinType.classId?.let { classId ->
        if (!classId.isLocal) {
          context.session.symbolProvider
            .getClassLikeSymbolByClassId(classId)
            ?.let { recordClass(it, context, isExplicit, collectTypeArguments, visited) }
        }
      }
    }
  }

  internal fun recordClass(
    firClass: FirClassLikeSymbol<*>,
    context: CheckerContext,
    isExplicit: Boolean = true,
    collectTypeArguments: Boolean = true,
    visited: MutableSet<Pair<ClassId, Boolean>> = mutableSetOf(),
  ) {
    val classIdAndIsExplicit = firClass.classId to isExplicit
    if (classIdAndIsExplicit in visited) {
      return
    } else {
      visited.add(classIdAndIsExplicit)
    }

    firClass.sourceElement?.binaryClass()?.let { addFile(it, isExplicit, context) }

    if (firClass is FirClassSymbol<*>) {
      firClass.resolvedSuperTypeRefs.forEach {
        recordTypeRef(it, context, false, collectTypeArguments, visited)
      }
      if (collectTypeArguments) {
        firClass.typeParameterSymbols
          .flatMap { it.resolvedBounds }
          .forEach { recordTypeRef(it, context, isExplicit, collectTypeArguments, visited) }
      }
    }
  }

  internal fun recordClass(
    binaryClass: String,
    context: CheckerContext,
    isExplicit: Boolean = true,
  ) {
    addFile(binaryClass, isExplicit, context)
  }

  private fun addFile(
    path: String,
    isExplicit: Boolean,
    context: CheckerContext,
  ) {
    val sourceFile = context.containingFile
    var jars = lastJars
    if (jars == null || sourceFile !== lastSourceFile) {
      jars = recordSource(sourceFile?.path.orEmpty())
      lastSourceFile = sourceFile
      lastJars = jars
    }
    val jar = classpathJarsByClass.getOrPut(path) { classpathJarOf(path).orEmpty() }
    if (jar.isEmpty()) {
      return
    }
    if (isExplicit) {
      jars.explicit.add(jar)
    } else {
      jars.implicit.add(jar)
    }
  }

  /**
   * Creates a mapping from canonical filesystem paths to original classpath paths.
   * This ensures jdeps uses the same paths that were on the compiler's classpath.
   * When multiple classpath entries point to the same canonical file, prefer runfiles paths.
   */
  private fun createCanonicalToClasspathMap(classpathEntries: List<String>): Map<String, String> {
    val mapping = mutableMapOf<String, String>()

    // Create canonical -> original mapping
    // Process entries and prefer runfiles paths over execroot paths
    classpathEntries.forEach { classpathPath ->
      val canonicalPath = canonicalizePath(classpathPath)
      val existing = mapping[canonicalPath]
      // Only update if no existing entry, or if current path is a runfiles path
      // and existing is not
      if (existing == null ||
        (classpathPath.contains("/runfiles/") && !existing.contains("/runfiles/"))
      ) {
        mapping[canonicalPath] = classpathPath
      }
    }
    return mapping
  }

  /**
   * The classpath entry of the jar a class is loaded from, or null if it is not loaded from a jar.
   * Uses the canonical-to-classpath mapping to preserve original classpath paths.
   */
  private fun classpathJarOf(classPath: String): String? {
    val jarPath = classPath.substringBefore("!/")
    if (!jarPath.endsWith(".jar")) {
      return null
    }
    return classpathJars.getOrPut(jarPath) {
      // Canonicalize for lookup so K2's forward-slash paths match classpath entries on Windows.
      canonicalToClasspath[canonicalizePath(jarPath)] ?: jarPath
    }
  }

  private fun canonicalizePath(path: String): String {
    val normalizedPath = if (File.separatorChar == '\\') path.replace('/', '\\') else path
    return try {
      File(normalizedPath).canonicalPath
    } catch (e: Exception) {
      try {
        Paths
          .get(normalizedPath)
          .toAbsolutePath()
          .normalize()
          .toString()
      } catch (_: Exception) {
        normalizedPath
      }
    }
  }
}

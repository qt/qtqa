// Copyright (C) 2025 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR LGPL-3.0-only OR GPL-2.0-only OR GPL-3.0-only

package org.qtproject.qt.android;

import jdk.javadoc.doclet.Doclet;
import jdk.javadoc.doclet.DocletEnvironment;
import jdk.javadoc.doclet.Reporter;
import com.sun.source.util.DocTrees;

import javax.tools.Diagnostic;
import javax.lang.model.SourceVersion;
import javax.lang.model.element.Element;
import javax.lang.model.element.ElementKind;
import javax.lang.model.element.ExecutableElement;
import javax.lang.model.element.Modifier;
import javax.lang.model.element.TypeElement;
import javax.lang.model.element.VariableElement;

import java.io.PrintWriter;
import java.util.List;
import java.util.Locale;
import java.util.Iterator;
import java.util.Set;
import java.util.stream.Collectors;

/**
 * Generate API signature description for Qt for Android Java APIs with their documentation.
 */
public class JavaApiSignature implements Doclet
{
    private Reporter m_reporter;
    private static String m_outputFileName = null;

    @Override
    public void init(Locale locale, Reporter reporter)
    {
        m_reporter = reporter;
    }

    @Override
    public String getName()
    {
        return "Qt Java API Signature";
    }

    @Override
    public Set<? extends Option> getSupportedOptions()
    {
        return Set.of(new OutputFileOption());
    }

    @Override
    public SourceVersion getSupportedSourceVersion()
    {
        return SourceVersion.latest();
    }

    @Override
    public boolean run(DocletEnvironment environment)
    {
        if (m_outputFileName == null || m_outputFileName.isEmpty()) {
            m_reporter.print(Diagnostic.Kind.ERROR,
                "No output file name provided, use the --output option to set it.");
            return false;
        }

        try (PrintWriter out = new PrintWriter(m_outputFileName)) {
            DocTrees docTrees = environment.getDocTrees();

            List<TypeElement> typeElements = environment.getIncludedElements().stream()
                .filter(e -> e.getKind() == ElementKind.CLASS
                          || e.getKind() == ElementKind.INTERFACE
                          || e.getKind() == ElementKind.ENUM)
                .filter(e -> e.getModifiers().contains(Modifier.PUBLIC))
                .map(e -> (TypeElement)e)
                .collect(Collectors.toList());

            for (int i = 0; i < typeElements.size(); ++i) {
                TypeElement type = typeElements.get(i);
                String kind = switch (type.getKind()) {
                    case INTERFACE -> "Interface";
                    case ENUM      -> "Enum";
                    default        -> "Class";
                };
                out.println(kind + ": " + type.getQualifiedName());

                String classDoc = getDocComment(docTrees, type);
                if (!classDoc.isEmpty())
                    out.println(formattedDocComment(classDoc));
                out.println();

                // Now handle all public enclosed elements
                for (Element enclosed : type.getEnclosedElements()) {
                    if (!enclosed.getModifiers().contains(Modifier.PUBLIC))
                        continue;

                    switch (enclosed.getKind()) {
                        case METHOD -> {
                            ExecutableElement m = (ExecutableElement) enclosed;
                            out.println("  Method: " + m.getSimpleName());
                            formattedDocSignature(out, docTrees, m);
                        }
                        case CONSTRUCTOR -> {
                            ExecutableElement ctor = (ExecutableElement) enclosed;
                            out.println("  Constructor: " + type.getSimpleName());
                            formattedDocSignature(out, docTrees, ctor);
                        }
                        case FIELD -> {
                            VariableElement f = (VariableElement) enclosed;
                            out.println("  Field: " + f.asType() + " " + f.getSimpleName());
                            String fldDoc = getDocComment(docTrees, f);
                            if (!fldDoc.isEmpty())
                                out.println(formattedDocComment(fldDoc));
                            out.println();
                        }
                        case CLASS, INTERFACE, ENUM -> {
                            TypeElement nested = (TypeElement) enclosed;
                            String nestedKind = (nested.getKind() == ElementKind.INTERFACE) ?
                                    "Nested Interface" :
                                 (nested.getKind() == ElementKind.ENUM) ?
                                    "Nested Enum" : "Nested Class";
                            out.println("  " + nestedKind + ": " + nested.getQualifiedName());
                            String nestedDoc = getDocComment(docTrees, nested);
                            if (!nestedDoc.isEmpty())
                                out.println(formattedDocComment(nestedDoc));
                            out.println();
                        }
                        case ENUM_CONSTANT -> {
                            out.println("  Enum Constant: " + enclosed.getSimpleName());
                            String constDoc = getDocComment(docTrees, enclosed);
                            if (!constDoc.isEmpty())
                                out.println(formattedDocComment(constDoc));
                            out.println();
                        }
                        default -> {
                            // For other things like annotations
                            String kindName = enclosed.getKind().name().replace('_', ' ');
                            out.println("  " + kindName + ": " + enclosed.getSimpleName());
                            String doc = getDocComment(docTrees, enclosed);
                            if (!doc.isEmpty())
                                out.println(formattedDocComment(doc));
                            out.println();
                        }
                    }
                }

                if (i < typeElements.size() - 1) {
                    out.println("--------------------------------------------------");
                    out.println();
                }
            }
        } catch (Exception e) {
            m_reporter.print(
                Diagnostic.Kind.ERROR, "Error generating API signature file: " + e.getMessage());
            return false;
        }
        return true;
    }

    /**
     * Helper to print formatted signature for methods and constructors
     */
    private void formattedDocSignature(PrintWriter out, DocTrees docTrees, ExecutableElement elem) {
        String doc = getDocComment(docTrees, elem);
        if (!doc.isEmpty())
            out.println(formattedDocComment(doc));

        // modifiers + return type (if any) + name + params
        String mods = elem.getModifiers().stream()
            .map(Modifier::toString)
            .collect(Collectors.joining(" "));
        if (!mods.isEmpty())
            mods += " ";

        String returnType = elem.getKind() == ElementKind.CONSTRUCTOR
            ? ""  // constructors have no return type
            : elem.getReturnType() + " ";

        String params = elem.getParameters().stream()
            .map(p -> p.asType() + " " + p.getSimpleName())
            .collect(Collectors.joining(", "));

        out.println("    " + mods + returnType + elem.getSimpleName()
                    + "(" + params + ")");
        out.println();
    }

    private String getDocComment(DocTrees docTrees, Element element)
    {
        var commentTree = docTrees.getDocCommentTree(element);
        return commentTree != null ? commentTree.toString() : "";
    }

    private static String formattedDocComment(String input)
    {
        if (input == null || input.isEmpty())
            return "";

        String[] lines = input.split("\\r?\\n");
        String content = java.util.Arrays.stream(lines)
            .map(line -> "    *    " + line.replaceAll("[ \\t\\u000B\\f]+", " ").trim())
            .collect(Collectors.joining(System.lineSeparator()));
        return "    /**" + System.lineSeparator() +
               content + System.lineSeparator() +
               "    */";
    }

    /**
     * Custom option to specify the output file name.
     * Usage: --output filename
     */
    private static class OutputFileOption implements Option
    {
        @Override
        public List<String> getNames()
        {
            return List.of("--output");
        }

        @Override
        public String getDescription()
        {
            return "Sets the output file name for the generated API signature (Mandatory).";
        }

        @Override
        public int getArgumentCount()
        {
            return 1;
        }

        @Override
        public Option.Kind getKind()
        {
            return Option.Kind.STANDARD;
        }

        @Override
        public String getParameters()
        {
            return "filename";
        }

        @Override
        public boolean process(String option, List<String> arguments)
        {
            m_outputFileName = arguments.get(0);
            return true;
        }
    }
}

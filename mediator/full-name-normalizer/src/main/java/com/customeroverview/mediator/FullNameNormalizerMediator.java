package com.customeroverview.mediator;

import org.apache.synapse.MessageContext;
import org.apache.synapse.SynapseLog;
import org.apache.synapse.mediators.AbstractMediator;

import java.util.Locale;
import java.util.regex.Pattern;

public class FullNameNormalizerMediator extends AbstractMediator {

    private static final Pattern WHITESPACE_PATTERN = Pattern.compile("[\\s\\u00A0]+");

    private String inputProperty = "rawFullName";
    private String outputProperty = "normalizedFullName";

    public String getInputProperty() {
        return inputProperty;
    }

    public void setInputProperty(String inputProperty) {
        if (inputProperty != null && !inputProperty.trim().isEmpty()) {
            this.inputProperty = inputProperty.trim();
        }
    }

    public String getOutputProperty() {
        return outputProperty;
    }

    public void setOutputProperty(String outputProperty) {
        if (outputProperty != null && !outputProperty.trim().isEmpty()) {
            this.outputProperty = outputProperty.trim();
        }
    }

    @Override
    public boolean mediate(MessageContext context) {
        SynapseLog synLog = getLog(context);
        Object rawValue = context.getProperty(inputProperty);
        String rawName = rawValue == null ? "" : rawValue.toString();

        String normalized = normalize(rawName);
        context.setProperty(outputProperty, normalized);

        Object traceId = context.getProperty("traceId");
        synLog.auditLog("FullNameNormalizerMediator executed | traceId=" + traceId
                + " | inputProperty=" + inputProperty
                + " | outputProperty=" + outputProperty);

        return true;
    }

    public static String normalize(String input) {
        if (input == null) {
            return "";
        }

        // Normalize Arabic Yeh/Kaf to standard Persian characters
        String unified = input
                .replace('\u064A', '\u06CC')
                .replace('\u0643', '\u06A9');

        // Trim and collapse all whitespace runs to a single space
        String collapsed = WHITESPACE_PATTERN.matcher(unified.trim()).replaceAll(" ");
        if (collapsed.isEmpty()) {
            return "";
        }

        String[] tokens = collapsed.split(" ");
        StringBuilder result = new StringBuilder(collapsed.length());

        for (int i = 0; i < tokens.length; i++) {
            if (i > 0) {
                result.append(' ');
            }
            result.append(titleCaseToken(tokens[i]));
        }

        return result.toString();
    }

    private static String titleCaseToken(String token) {
        if (token.isEmpty()) {
            return token;
        }
        String lower = token.toLowerCase(Locale.ROOT);
        int firstCodePoint = lower.codePointAt(0);
        if (Character.isLetter(firstCodePoint)) {
            int firstCharLen = Character.charCount(firstCodePoint);
            String first = lower.substring(0, firstCharLen).toUpperCase(Locale.ROOT);
            return first + lower.substring(firstCharLen);
        }
        return lower;
    }
}

use wasm_bindgen::prelude::*;

#[derive(Debug, Clone, PartialEq)]
pub enum CalcError {
    EmptyExpression,
    InvalidToken(char),
    MismatchedParentheses,
    DivisionByZero,
    MalformedExpression,
}

impl CalcError {
    fn message(&self) -> &'static str {
        match self {
            CalcError::EmptyExpression => "Expression is empty.",
            CalcError::InvalidToken(_) => "Expression contains an invalid character.",
            CalcError::MismatchedParentheses => "Parentheses are mismatched.",
            CalcError::DivisionByZero => "Division by zero is not allowed.",
            CalcError::MalformedExpression => "Expression is malformed.",
        }
    }
}

#[derive(Debug, Clone, PartialEq)]
enum Token {
    Number(f64),
    Op(Operator),
    LParen,
    RParen,
}

#[derive(Debug, Copy, Clone, PartialEq)]
enum Operator {
    Add,
    Sub,
    Mul,
    Div,
}

impl Operator {
    fn precedence(self) -> u8 {
        match self {
            Operator::Add | Operator::Sub => 1,
            Operator::Mul | Operator::Div => 2,
        }
    }

    fn apply(self, left: f64, right: f64) -> Result<f64, CalcError> {
        match self {
            Operator::Add => Ok(left + right),
            Operator::Sub => Ok(left - right),
            Operator::Mul => Ok(left * right),
            Operator::Div => {
                if right == 0.0 {
                    return Err(CalcError::DivisionByZero);
                }
                Ok(left / right)
            }
        }
    }
}

#[wasm_bindgen]
pub fn evaluate_expression(input: &str) -> Result<f64, JsValue> {
    evaluate(input).map_err(|err| JsValue::from_str(err.message()))
}

pub fn evaluate(input: &str) -> Result<f64, CalcError> {
    let tokens = tokenize(input)?;
    let rpn = to_rpn(&tokens)?;
    eval_rpn(&rpn)
}

fn tokenize(input: &str) -> Result<Vec<Token>, CalcError> {
    let trimmed = input.trim();
    if trimmed.is_empty() {
        return Err(CalcError::EmptyExpression);
    }

    let mut chars = trimmed.chars().peekable();
    let mut tokens = Vec::new();
    let mut expect_unary = true;

    while let Some(&ch) = chars.peek() {
        match ch {
            ' ' | '\t' | '\n' | '\r' => {
                chars.next();
            }
            '0'..='9' | '.' => {
                let mut number = String::new();
                while let Some(&c) = chars.peek() {
                    if c.is_ascii_digit() || c == '.' {
                        number.push(c);
                        chars.next();
                    } else {
                        break;
                    }
                }

                let parsed = number.parse::<f64>().map_err(|_| CalcError::MalformedExpression)?;
                tokens.push(Token::Number(parsed));
                expect_unary = false;
            }
            '+' => {
                chars.next();
                tokens.push(Token::Op(Operator::Add));
                expect_unary = true;
            }
            '-' => {
                chars.next();
                if expect_unary {
                    let mut number = String::from("-");
                    while let Some(&c) = chars.peek() {
                        if c.is_ascii_digit() || c == '.' {
                            number.push(c);
                            chars.next();
                        } else {
                            break;
                        }
                    }
                    if number == "-" {
                        return Err(CalcError::MalformedExpression);
                    }
                    let parsed = number.parse::<f64>().map_err(|_| CalcError::MalformedExpression)?;
                    tokens.push(Token::Number(parsed));
                    expect_unary = false;
                } else {
                    tokens.push(Token::Op(Operator::Sub));
                    expect_unary = true;
                }
            }
            '*' => {
                chars.next();
                tokens.push(Token::Op(Operator::Mul));
                expect_unary = true;
            }
            '/' => {
                chars.next();
                tokens.push(Token::Op(Operator::Div));
                expect_unary = true;
            }
            '(' => {
                chars.next();
                tokens.push(Token::LParen);
                expect_unary = true;
            }
            ')' => {
                chars.next();
                tokens.push(Token::RParen);
                expect_unary = false;
            }
            _ => return Err(CalcError::InvalidToken(ch)),
        }
    }

    Ok(tokens)
}

fn to_rpn(tokens: &[Token]) -> Result<Vec<Token>, CalcError> {
    let mut output = Vec::new();
    let mut operators: Vec<Token> = Vec::new();

    for token in tokens {
        match token {
            Token::Number(_) => output.push(token.clone()),
            Token::Op(op) => {
                while let Some(Token::Op(top_op)) = operators.last() {
                    if top_op.precedence() >= op.precedence() {
                        output.push(operators.pop().ok_or(CalcError::MalformedExpression)?);
                    } else {
                        break;
                    }
                }
                operators.push(token.clone());
            }
            Token::LParen => operators.push(Token::LParen),
            Token::RParen => {
                let mut found_lparen = false;
                while let Some(top) = operators.pop() {
                    if top == Token::LParen {
                        found_lparen = true;
                        break;
                    }
                    output.push(top);
                }
                if !found_lparen {
                    return Err(CalcError::MismatchedParentheses);
                }
            }
        }
    }

    while let Some(top) = operators.pop() {
        if top == Token::LParen {
            return Err(CalcError::MismatchedParentheses);
        }
        output.push(top);
    }

    Ok(output)
}

fn eval_rpn(tokens: &[Token]) -> Result<f64, CalcError> {
    let mut stack: Vec<f64> = Vec::new();

    for token in tokens {
        match token {
            Token::Number(value) => stack.push(*value),
            Token::Op(op) => {
                let right = stack.pop().ok_or(CalcError::MalformedExpression)?;
                let left = stack.pop().ok_or(CalcError::MalformedExpression)?;
                let result = op.apply(left, right)?;
                stack.push(result);
            }
            Token::LParen | Token::RParen => return Err(CalcError::MalformedExpression),
        }
    }

    if stack.len() != 1 {
        return Err(CalcError::MalformedExpression);
    }

    Ok(stack[0])
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn handles_operator_precedence() {
        let result = evaluate("2 + 3 * 4").unwrap();
        assert_eq!(result, 14.0);
    }

    #[test]
    fn handles_parentheses() {
        let result = evaluate("(2 + 3) * 4").unwrap();
        assert_eq!(result, 20.0);
    }

    #[test]
    fn handles_unary_negative_numbers() {
        let result = evaluate("-2.5 * 4").unwrap();
        assert_eq!(result, -10.0);
    }

    #[test]
    fn reports_division_by_zero() {
        let err = evaluate("10 / 0").unwrap_err();
        assert_eq!(err, CalcError::DivisionByZero);
    }

    #[test]
    fn reports_invalid_token() {
        let err = evaluate("2 + a").unwrap_err();
        assert_eq!(err, CalcError::InvalidToken('a'));
    }

    #[test]
    fn reports_mismatched_parentheses() {
        let err = evaluate("(2 + 3").unwrap_err();
        assert_eq!(err, CalcError::MismatchedParentheses);
    }

    #[test]
    fn reports_empty_expression() {
        let err = evaluate("  ").unwrap_err();
        assert_eq!(err, CalcError::EmptyExpression);
    }
}

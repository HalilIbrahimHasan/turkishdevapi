package post_http_request_method;

import base_urls.HerokuappBaseUrl;
import io.restassured.http.ContentType;
import io.restassured.response.Response;
import org.junit.Test;

import java.util.HashMap;
import java.util.Map;

import static io.restassured.RestAssured.given;
import static org.junit.Assert.assertEquals;

public class Post01 extends HerokuappBaseUrl {




      /*
        When
	 		I send POST Request to the Url https://restful-booker.herokuapp.com/booking
	 		with the request body {
								    "firstname": "Erdem",
								    "lastname": "Gocen",
								    "totalprice": 11111,
								    "depositpaid": true,
								    "bookingdates": {
								        "checkin": "2022-09-09",
								        "checkout": "2022-09-21"
								     }
								  }
	 	Then
	 		Status code is 200
	 		And response body should be like {
											    "bookingid": 11,
											    "booking": {
											        "firstname": "Erdem",
											        "lastname": "Gocen",
											        "totalprice": 11111,
											        "depositpaid": true,
											        "bookingdates": {
											            "checkin": "2022-09-09",
											            "checkout": "2022-09-21"
											        }
											    }
											 }
     */

    @Test
    public void post01(){

        //Set the url
        spec.pathParam("bir", "booking");


        //Set the expected data / beklenen datayi olusturunuz
        Map<String, Object> bookingdates = new HashMap<>();
        bookingdates.put("checkin", "2022-09-09");
        bookingdates.put("checkout", "2022-09-21");

        Map<String, Object> expectedData = new HashMap<>();
        expectedData.put("firstname", "Erdem");
        expectedData.put("lastname", "Gocen");
        expectedData.put("totalprice", 11111);
        expectedData.put("depositpaid", true);
        expectedData.put("bookingdates", bookingdates);

        //Send the Post Request and get the response / Post request gonderiniz ve response elde ediniz
        Response response = given().spec(spec).contentType(ContentType.JSON).body(expectedData).when().post("/{bir}");

        response.prettyPrint();


        //validate

        Map<String, Object> actualData = response.as(HashMap.class);

        System.out.println(actualData);

        assertEquals(expectedData.get("firstname"),((Map) actualData.get("booking")).get("firstname"));
        assertEquals(expectedData.get("lastname"),((Map) actualData.get("booking")).get("lastname"));
        assertEquals(expectedData.get("lastname"),((Map) actualData.get("booking")).get("lastname"));
        assertEquals(expectedData.get("depositpaid"),((Map) actualData.get("booking")).get("depositpaid"));

//        assertEquals(expectedData.get("lastname"), actualData.get("lastname"));
//        assertEquals(expectedData.get("totalprice"), actualData.get("totalprice"));
//        assertEquals(expectedData.get("depositpaid"), actualData.get("depositpaid"));
//
//
//        assertEquals(bookingdates.get("checkin"), ((Map)actualData.get("bookingdates")).get("checkin"));





        assertEquals(bookingdates.get("checkin"),((Map)((Map) actualData.get("booking")).get("bookingdates")).get("checkin"));
        assertEquals(bookingdates.get("checkout"),((Map)((Map) actualData.get("booking")).get("bookingdates")).get("checkout"));

//        assertEquals(bookingdates.get("checkout"), ((Map)actualData.get("bookingdates")).get("checkout"));
    }




}
